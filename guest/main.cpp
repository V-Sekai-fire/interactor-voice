// voice.elf: the voice codec as a godot-sandbox guest. The host passes 16-bit PCM frames and packets
// as byte arrays; carrying the packets (as WebTransport datagrams) is the host's and the zone's job.
#include <api.hpp>

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "voice_codec.h"

static VoiceEncoder *g_encoder = nullptr;
static VoiceDecoder *g_decoder = nullptr;

static Variant text(const std::string &p_text) {
	return Variant(String(p_text));
}

static Variant bytes(const uint8_t *p_data, size_t p_size) {
	return Variant(PackedArray<uint8_t>(p_data, p_size));
}

static Variant voice_open() {
	voice_encoder_free(g_encoder);
	voice_decoder_free(g_decoder);
	g_encoder = voice_encoder_new();
	g_decoder = voice_decoder_new();
	if (g_encoder == nullptr || g_decoder == nullptr) {
		return text("FAIL: the Opus encoder or decoder did not open");
	}
	return text("OK " + std::to_string(VOICE_SAMPLE_RATE) + " Hz, " + std::to_string(VOICE_FRAME) +
			" samples a frame, lookahead " + std::to_string(voice_lookahead(g_encoder)));
}

static Variant voice_encode_frame(PackedArray<uint8_t> p_pcm) {
	const std::vector<uint8_t> pcm = p_pcm.fetch();
	if (g_encoder == nullptr || pcm.size() != size_t(VOICE_FRAME) * sizeof(int16_t)) {
		return bytes(nullptr, 0);
	}
	int16_t samples[VOICE_FRAME];
	std::memcpy(samples, pcm.data(), sizeof samples);
	uint8_t packet[VOICE_MAX_PACKET];
	const int size = voice_encode(g_encoder, samples, packet, VOICE_MAX_PACKET);
	return bytes(packet, size > 0 ? size_t(size) : 0);
}

static Variant voice_decode_packet(PackedArray<uint8_t> p_packet) {
	const std::vector<uint8_t> packet = p_packet.fetch();
	static constexpr int kMaxFrames = 8;
	std::vector<int16_t> pcm(size_t(kMaxFrames) * VOICE_FRAME);
	const int frames = g_decoder == nullptr ? -1 :
			voice_decode(g_decoder, packet.data(), int(packet.size()), pcm.data(), kMaxFrames);
	if (frames <= 0) {
		return bytes(nullptr, 0);
	}
	return bytes(reinterpret_cast<const uint8_t *>(pcm.data()), size_t(frames) * VOICE_FRAME * sizeof(int16_t));
}

static Variant voice_stats() {
	if (g_decoder == nullptr) {
		return text("FAIL: voice_open first");
	}
	return text("received " + std::to_string(voice_received(g_decoder)) + " concealed " +
			std::to_string(voice_concealed(g_decoder)) + " late " + std::to_string(voice_late(g_decoder)));
}

int main() {
	ADD_API_FUNCTION(voice_open, "String", "", "Open a fresh encoder and decoder (48 kHz mono, 20 ms frames)");
	ADD_API_FUNCTION(voice_encode_frame, "PackedByteArray", "PackedByteArray pcm",
			"One frame of 960 16-bit samples to a sequenced Opus packet");
	ADD_API_FUNCTION(voice_decode_packet, "PackedByteArray", "PackedByteArray packet",
			"One packet to 16-bit samples: concealed frames for any missing packets, then its own");
	ADD_API_FUNCTION(voice_stats, "String", "", "Packets received, frames concealed, late packets dropped");
	halt();
}
