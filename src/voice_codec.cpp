#include "voice_codec.h"

#include <opus.h>

#include <stdlib.h>

struct VoiceEncoder {
	OpusEncoder *opus;
	uint16_t sequence;
};

// Zeroed by calloc: not started, nothing received.
struct VoiceDecoder {
	OpusDecoder *opus;
	bool started;
	uint16_t expected;
	uint32_t received;
	uint32_t concealed;
	uint32_t late;
};

// The speech module's settings: full-band audio at 128 kbit/s, highest complexity, in-band FEC
// sized for 10% loss.
VoiceEncoder *voice_encoder_new(void) {
	int error = OPUS_OK;
	OpusEncoder *opus = opus_encoder_create(VOICE_SAMPLE_RATE, 1, OPUS_APPLICATION_AUDIO, &error);
	if (error != OPUS_OK || opus == nullptr) {
		return nullptr;
	}
	opus_encoder_ctl(opus, OPUS_SET_BITRATE(128000));
	opus_encoder_ctl(opus, OPUS_SET_COMPLEXITY(10));
	opus_encoder_ctl(opus, OPUS_SET_SIGNAL(OPUS_SIGNAL_MUSIC));
	opus_encoder_ctl(opus, OPUS_SET_INBAND_FEC(1));
	opus_encoder_ctl(opus, OPUS_SET_PACKET_LOSS_PERC(10));
	VoiceEncoder *encoder = static_cast<VoiceEncoder *>(calloc(1, sizeof(VoiceEncoder)));
	if (encoder == nullptr) {
		opus_encoder_destroy(opus);
		return nullptr;
	}
	encoder->opus = opus;
	return encoder;
}

void voice_encoder_free(VoiceEncoder *p_encoder) {
	if (p_encoder != nullptr) {
		opus_encoder_destroy(p_encoder->opus);
		free(p_encoder);
	}
}

int voice_encode(VoiceEncoder *p_encoder, const int16_t *p_pcm, uint8_t *r_packet, int p_capacity) {
	if (p_encoder == nullptr || p_capacity <= VOICE_HEADER) {
		return OPUS_BAD_ARG;
	}
	const opus_int32 bytes = opus_encode(p_encoder->opus, p_pcm, VOICE_FRAME, r_packet + VOICE_HEADER,
			p_capacity - VOICE_HEADER);
	if (bytes < 0) {
		return bytes;
	}
	r_packet[0] = uint8_t(p_encoder->sequence & 0xff);
	r_packet[1] = uint8_t(p_encoder->sequence >> 8);
	p_encoder->sequence = uint16_t(p_encoder->sequence + 1);
	return bytes + VOICE_HEADER;
}

int voice_lookahead(VoiceEncoder *p_encoder) {
	opus_int32 samples = 0;
	opus_encoder_ctl(p_encoder->opus, OPUS_GET_LOOKAHEAD(&samples));
	return samples;
}

VoiceDecoder *voice_decoder_new(void) {
	int error = OPUS_OK;
	OpusDecoder *opus = opus_decoder_create(VOICE_SAMPLE_RATE, 1, &error);
	if (error != OPUS_OK || opus == nullptr) {
		return nullptr;
	}
	VoiceDecoder *decoder = static_cast<VoiceDecoder *>(calloc(1, sizeof(VoiceDecoder)));
	if (decoder == nullptr) {
		opus_decoder_destroy(opus);
		return nullptr;
	}
	decoder->opus = opus;
	return decoder;
}

void voice_decoder_free(VoiceDecoder *p_decoder) {
	if (p_decoder != nullptr) {
		opus_decoder_destroy(p_decoder->opus);
		free(p_decoder);
	}
}

int voice_decode(VoiceDecoder *p_decoder, const uint8_t *p_packet, int p_size, int16_t *r_pcm, int p_max_frames) {
	if (p_decoder == nullptr || p_size <= VOICE_HEADER || p_max_frames < 1) {
		return OPUS_BAD_ARG;
	}
	const uint16_t sequence = uint16_t(p_packet[0] | (p_packet[1] << 8));
	if (!p_decoder->started) {
		p_decoder->started = true;
		p_decoder->expected = sequence;
	}
	const uint16_t gap = uint16_t(sequence - p_decoder->expected);
	if (gap >= 0x8000) {
		p_decoder->late++;
		return 0;
	}
	const unsigned char *payload = p_packet + VOICE_HEADER;
	const opus_int32 payload_size = p_size - VOICE_HEADER;
	int frames = 0;
	for (uint32_t k = 0; k < gap && frames < p_max_frames - 1; ++k) {
		// The frame just before this packet can come from this packet's FEC; earlier ones are PLC.
		const bool from_fec = k + 1 == gap;
		const int samples = opus_decode(p_decoder->opus, from_fec ? payload : nullptr, from_fec ? payload_size : 0,
				r_pcm + frames * VOICE_FRAME, VOICE_FRAME, from_fec ? 1 : 0);
		if (samples < 0) {
			return samples;
		}
		frames++;
	}
	p_decoder->concealed += gap;
	const int samples = opus_decode(p_decoder->opus, payload, payload_size, r_pcm + frames * VOICE_FRAME, VOICE_FRAME, 0);
	if (samples < 0) {
		return samples;
	}
	frames++;
	p_decoder->received++;
	p_decoder->expected = uint16_t(sequence + 1);
	return frames;
}

uint32_t voice_received(const VoiceDecoder *p_decoder) {
	return p_decoder->received;
}

uint32_t voice_concealed(const VoiceDecoder *p_decoder) {
	return p_decoder->concealed;
}

uint32_t voice_late(const VoiceDecoder *p_decoder) {
	return p_decoder->late;
}
