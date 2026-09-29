// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Lean bindings over src/voice_codec: a candidate signal from a seed, sent through the codec as the
// guest does, with one packet lost, hidden or repeated, and the result as a FloatArray. Plain C
// buffers only: the executable links with Lean's toolchain, which carries no C++ library.
#include "voice_codec.h"

#include <lean/lean.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

namespace {

constexpr int kWarmup = 4;
constexpr int kMaxFrames = 64;

struct Pcm {
	int16_t *samples;
	size_t count;
};

// A tone whose pitch and level change every frame, so concealment cannot predict a lost frame.
void fill_signal(uint32_t p_seed, int p_frames, int16_t *r_samples) {
	double phase = 0.0;
	for (int f = 0; f < p_frames; ++f) {
		const uint32_t h = p_seed * 2654435761u + uint32_t(f) * 40503u;
		const double hz = 150.0 + double(h % 2000);
		const double amp = 3000.0 + double((h / 7) % 9000);
		for (int i = 0; i < VOICE_FRAME; ++i) {
			phase += 2.0 * M_PI * hz / VOICE_SAMPLE_RATE;
			r_samples[size_t(f) * VOICE_FRAME + i] = int16_t(amp * sin(phase));
		}
	}
}

double frame_snr(const int16_t *p_in, const Pcm &p_out, int p_frame, int p_delay) {
	double signal = 0.0;
	double error = 0.0;
	for (int i = 0; i < VOICE_FRAME; ++i) {
		const size_t t = size_t(p_frame) * VOICE_FRAME + i;
		const double a = p_in[t];
		const double b = t + p_delay < p_out.count ? p_out.samples[t + p_delay] : 0.0;
		signal += a * a;
		error += (a - b) * (a - b);
	}
	return 10.0 * log10(signal / (error + 1e-9));
}

lean_obj_res floats(const double *p_values, size_t p_count) {
	lean_object *out = lean_alloc_sarray(sizeof(double), p_count, p_count);
	memcpy(lean_float_array_cptr(out), p_values, p_count * sizeof(double));
	return out;
}

// Encodes the signal frame by frame and decodes it as the guest does. Mode 0 delivers every packet,
// 1 loses packet p_at, 2 loses it and renumbers every later packet, 3 sends it twice.
Pcm transmit(VoiceEncoder *p_encoder, VoiceDecoder *p_decoder, const int16_t *p_in, int p_frames, uint32_t p_at,
		uint8_t p_mode) {
	Pcm out = {static_cast<int16_t *>(calloc(size_t(p_frames + 8) * VOICE_FRAME, sizeof(int16_t))), 0};
	int16_t pcm[8 * VOICE_FRAME];
	uint8_t packet[VOICE_MAX_PACKET];
	for (int f = 0; f < p_frames; ++f) {
		const int size = voice_encode(p_encoder, p_in + size_t(f) * VOICE_FRAME, packet, VOICE_MAX_PACKET);
		if ((p_mode == 1 || p_mode == 2) && uint32_t(f) == p_at) {
			continue;
		}
		if (p_mode == 2 && uint32_t(f) > p_at) {
			const uint16_t sequence = uint16_t((packet[0] | (packet[1] << 8)) - 1);
			packet[0] = uint8_t(sequence & 0xff);
			packet[1] = uint8_t(sequence >> 8);
		}
		const int repeats = p_mode == 3 && uint32_t(f) == p_at ? 2 : 1;
		for (int r = 0; r < repeats; ++r) {
			const int got = voice_decode(p_decoder, packet, size, pcm, 8);
			for (int k = 0; k < got && out.count / VOICE_FRAME < size_t(p_frames + 8); ++k) {
				memcpy(out.samples + out.count, pcm + size_t(k) * VOICE_FRAME, VOICE_FRAME * sizeof(int16_t));
				out.count += VOICE_FRAME;
			}
		}
	}
	return out;
}

} // namespace

// Returns [concealed, late, frames out, worst SNR in dB over the frames from kWarmup on that a loss
// does not touch, lookahead, worst SNR of the two frames after a lost one, where the decoder is still
// settling out of concealment].
extern "C" lean_obj_res vt_lean_roundtrip(uint32_t p_seed, uint32_t p_frames, uint32_t p_at, uint8_t p_mode,
		uint32_t p_delay) {
	const int frames = p_frames > kMaxFrames ? kMaxFrames : int(p_frames);
	int16_t *in = static_cast<int16_t *>(calloc(size_t(frames) * VOICE_FRAME, sizeof(int16_t)));
	fill_signal(p_seed, frames, in);
	VoiceEncoder *encoder = voice_encoder_new();
	VoiceDecoder *decoder = voice_decoder_new();
	Pcm out = transmit(encoder, decoder, in, frames, p_at, p_mode);
	const bool lossy = p_mode == 1 || p_mode == 2;
	double worst = 1e9;
	double beside = 1e9;
	for (int f = kWarmup; f < frames - 1; ++f) {
		const int64_t d = int64_t(f) - int64_t(p_at);
		if (lossy && d == 0) {
			continue;
		}
		const double snr = frame_snr(in, out, f, int(p_delay));
		if (lossy && (d == 1 || d == 2)) {
			beside = fmin(beside, snr);
		} else {
			worst = fmin(worst, snr);
		}
	}
	const double result[6] = {double(voice_concealed(decoder)), double(voice_late(decoder)),
		double(out.count / VOICE_FRAME), worst, double(voice_lookahead(encoder)), beside};
	voice_encoder_free(encoder);
	voice_decoder_free(decoder);
	free(out.samples);
	free(in);
	return floats(result, 6);
}

// The delay, in samples, at which the decoded signal best matches the input.
extern "C" uint32_t vt_lean_best_delay(uint32_t p_seed) {
	const int frames = 24;
	int16_t *in = static_cast<int16_t *>(calloc(size_t(frames) * VOICE_FRAME, sizeof(int16_t)));
	fill_signal(p_seed, frames, in);
	VoiceEncoder *encoder = voice_encoder_new();
	VoiceDecoder *decoder = voice_decoder_new();
	Pcm out = transmit(encoder, decoder, in, frames, 0, 0);
	voice_encoder_free(encoder);
	voice_decoder_free(decoder);
	uint32_t best = 0;
	double best_snr = -1e9;
	for (uint32_t delay = 0; delay < 2 * VOICE_FRAME; ++delay) {
		double signal = 0.0;
		double error = 0.0;
		for (size_t t = size_t(kWarmup) * VOICE_FRAME; t < size_t(frames - 2) * VOICE_FRAME; ++t) {
			const double a = in[t];
			const double b = out.samples[t + delay];
			signal += a * a;
			error += (a - b) * (a - b);
		}
		const double snr = 10.0 * log10(signal / (error + 1e-9));
		if (snr > best_snr) {
			best_snr = snr;
			best = delay;
		}
	}
	free(out.samples);
	free(in);
	return best;
}
