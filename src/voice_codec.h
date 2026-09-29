// voice_codec: speech as Opus packets, one 20 ms frame at 48 kHz mono per packet, each packet led by
// a 16-bit little-endian sequence number so the receiver knows which frames never arrived.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
	VOICE_SAMPLE_RATE = 48000,
	VOICE_FRAME = 960,
	VOICE_HEADER = 2,
	VOICE_MAX_PACKET = 4000 + VOICE_HEADER,
};

typedef struct VoiceEncoder VoiceEncoder;
typedef struct VoiceDecoder VoiceDecoder;

VoiceEncoder *voice_encoder_new(void);
void voice_encoder_free(VoiceEncoder *p_encoder);
// One frame of VOICE_FRAME samples in; the packet's size in bytes out, or a negative Opus error.
int voice_encode(VoiceEncoder *p_encoder, const int16_t *p_pcm, uint8_t *r_packet, int p_capacity);
// Samples the decoded signal trails the input by.
int voice_lookahead(VoiceEncoder *p_encoder);

VoiceDecoder *voice_decoder_new(void);
void voice_decoder_free(VoiceDecoder *p_decoder);
// One packet in; frames of VOICE_FRAME samples out: one concealed frame for each packet the sequence
// says is missing (at most p_max_frames - 1), then the packet's own. Returns frames written, 0 for a
// late or repeated packet, or a negative Opus error.
int voice_decode(VoiceDecoder *p_decoder, const uint8_t *p_packet, int p_size, int16_t *r_pcm, int p_max_frames);
uint32_t voice_received(const VoiceDecoder *p_decoder);
uint32_t voice_concealed(const VoiceDecoder *p_decoder);
uint32_t voice_late(const VoiceDecoder *p_decoder);

#ifdef __cplusplus
}
#endif
