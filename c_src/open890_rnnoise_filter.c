#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rnnoise.h>

#define FRAME_16K 160
#define FRAME_48K 480

static int read_exact(uint8_t *buf, size_t len) {
  size_t got = 0;
  while (got < len) {
    size_t n = fread(buf + got, 1, len - got, stdin);
    if (n == 0) {
      if (feof(stdin)) {
        return 0;
      }
      if (ferror(stdin)) {
        return -1;
      }
    }
    got += n;
  }
  return 1;
}

static int write_exact(const uint8_t *buf, size_t len) {
  size_t written = 0;
  while (written < len) {
    size_t n = fwrite(buf + written, 1, len - written, stdout);
    if (n == 0) {
      return 0;
    }
    written += n;
  }
  return fflush(stdout) == 0;
}

static int16_t decode_i16_le(const uint8_t *p) {
  uint16_t lo = (uint16_t)p[0];
  uint16_t hi = (uint16_t)p[1] << 8;
  return (int16_t)(lo | hi);
}

static void encode_i16_le(uint8_t *p, int16_t v) {
  p[0] = (uint8_t)(v & 0xFF);
  p[1] = (uint8_t)((uint16_t)v >> 8);
}

static int16_t clamp_i16(float x) {
  if (x > 32767.0f) {
    return 32767;
  }
  if (x < -32768.0f) {
    return -32768;
  }
  if (x >= 0.0f) {
    return (int16_t)(x + 0.5f);
  }
  return (int16_t)(x - 0.5f);
}

static void upsample_16k_to_48k(const int16_t *in160, float *out480) {
  for (int i = 0; i < FRAME_16K; i++) {
    float s0 = (float)in160[i];
    float s1 = (float)((i + 1 < FRAME_16K) ? in160[i + 1] : in160[i]);
    out480[(i * 3) + 0] = s0;
    out480[(i * 3) + 1] = ((2.0f * s0) + s1) / 3.0f;
    out480[(i * 3) + 2] = (s0 + (2.0f * s1)) / 3.0f;
  }
}

static void downsample_48k_to_16k(const float *in480, int16_t *out160) {
  for (int i = 0; i < FRAME_16K; i++) {
    out160[i] = clamp_i16(in480[i * 3]);
  }
}

static void process_samples(DenoiseState *state, int16_t *samples, size_t sample_count) {
  float in48[FRAME_48K];
  float out48[FRAME_48K];

  size_t offset = 0;
  while (offset + FRAME_16K <= sample_count) {
    upsample_16k_to_48k(samples + offset, in48);
    rnnoise_process_frame(state, out48, in48);
    downsample_48k_to_16k(out48, samples + offset);
    offset += FRAME_16K;
  }
}

int main(void) {
  DenoiseState *state = rnnoise_create(NULL);
  if (state == NULL) {
    return 2;
  }

  uint8_t lenbuf[4];
  uint8_t *packet = NULL;
  size_t packet_cap = 0;
  int16_t *samples = NULL;
  size_t samples_cap = 0;

  while (1) {
    int rr = read_exact(lenbuf, sizeof(lenbuf));
    if (rr == 0) {
      break;
    }
    if (rr < 0) {
      break;
    }

    uint32_t len = ((uint32_t)lenbuf[0] << 24) | ((uint32_t)lenbuf[1] << 16) |
                   ((uint32_t)lenbuf[2] << 8) | (uint32_t)lenbuf[3];

    if (len < 4) {
      break;
    }

    if ((size_t)len > packet_cap) {
      uint8_t *next_packet = (uint8_t *)realloc(packet, len);
      if (next_packet == NULL) {
        break;
      }
      packet = next_packet;
      packet_cap = len;
    }

    if (read_exact(packet, len) <= 0) {
      break;
    }

    size_t audio_len = (size_t)len - 4;
    size_t sample_count = audio_len / 2;

    if (sample_count > samples_cap) {
      int16_t *next_samples = (int16_t *)realloc(samples, sample_count * sizeof(int16_t));
      if (next_samples == NULL) {
        break;
      }
      samples = next_samples;
      samples_cap = sample_count;
    }

    for (size_t i = 0; i < sample_count; i++) {
      samples[i] = decode_i16_le(packet + 4 + (i * 2));
    }

    process_samples(state, samples, sample_count);

    for (size_t i = 0; i < sample_count; i++) {
      encode_i16_le(packet + 4 + (i * 2), samples[i]);
    }

    if (!write_exact(lenbuf, sizeof(lenbuf))) {
      break;
    }

    if (!write_exact(packet, len)) {
      break;
    }
  }

  rnnoise_destroy(state);
  free(packet);
  free(samples);

  return 0;
}
