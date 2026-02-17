#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_DECODES 64
#define MAX_MESSAGE_LEN 255

typedef struct {
  int snr;
  float dt;
  float freq_hz;
  char text[MAX_MESSAGE_LEN + 1];
} decode_t;

typedef struct {
  char *buf;
  size_t len;
  size_t cap;
} sb_t;

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

static void trim_right(char *s) {
  size_t n = strlen(s);
  while (n > 0 && isspace((unsigned char)s[n - 1])) {
    s[n - 1] = '\0';
    n--;
  }
}

static int sb_init(sb_t *sb, size_t cap) {
  sb->buf = (char *)malloc(cap);
  if (sb->buf == NULL) {
    return 0;
  }
  sb->len = 0;
  sb->cap = cap;
  sb->buf[0] = '\0';
  return 1;
}

static int sb_ensure(sb_t *sb, size_t extra) {
  if (sb->len + extra + 1 <= sb->cap) {
    return 1;
  }

  size_t next_cap = sb->cap;
  while (sb->len + extra + 1 > next_cap) {
    next_cap *= 2;
  }

  char *next = (char *)realloc(sb->buf, next_cap);
  if (next == NULL) {
    return 0;
  }

  sb->buf = next;
  sb->cap = next_cap;
  return 1;
}

static int sb_append(sb_t *sb, const char *s) {
  size_t n = strlen(s);
  if (!sb_ensure(sb, n)) {
    return 0;
  }

  memcpy(sb->buf + sb->len, s, n);
  sb->len += n;
  sb->buf[sb->len] = '\0';
  return 1;
}

static int sb_appendf(sb_t *sb, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  va_list ap2;
  va_copy(ap2, ap);

  int needed = vsnprintf(NULL, 0, fmt, ap);
  va_end(ap);
  if (needed < 0) {
    va_end(ap2);
    return 0;
  }

  if (!sb_ensure(sb, (size_t)needed)) {
    va_end(ap2);
    return 0;
  }

  vsnprintf(sb->buf + sb->len, sb->cap - sb->len, fmt, ap2);
  va_end(ap2);

  sb->len += (size_t)needed;
  return 1;
}

static int sb_append_json_string(sb_t *sb, const char *s) {
  if (!sb_append(sb, "\"")) {
    return 0;
  }

  for (const unsigned char *p = (const unsigned char *)s; *p != '\0'; p++) {
    unsigned char c = *p;
    switch (c) {
      case '\\':
        if (!sb_append(sb, "\\\\")) {
          return 0;
        }
        break;
      case '"':
        if (!sb_append(sb, "\\\"")) {
          return 0;
        }
        break;
      case '\n':
        if (!sb_append(sb, "\\n")) {
          return 0;
        }
        break;
      case '\r':
        if (!sb_append(sb, "\\r")) {
          return 0;
        }
        break;
      case '\t':
        if (!sb_append(sb, "\\t")) {
          return 0;
        }
        break;
      default:
        if (c < 0x20) {
          if (!sb_appendf(sb, "\\u%04x", (unsigned)c)) {
            return 0;
          }
        } else {
          char tmp[2] = {(char)c, '\0'};
          if (!sb_append(sb, tmp)) {
            return 0;
          }
        }
    }
  }

  if (!sb_append(sb, "\"")) {
    return 0;
  }

  return 1;
}

static void sb_free(sb_t *sb) {
  free(sb->buf);
  sb->buf = NULL;
  sb->len = 0;
  sb->cap = 0;
}

static size_t resample_16k_to_12k(const int16_t *in, size_t in_count, int16_t *out) {
  if (in_count < 2) {
    return 0;
  }

  size_t out_count = (in_count * 3) / 4;

  for (size_t i = 0; i < out_count; i++) {
    size_t src_num = i * 4;
    size_t j = src_num / 3;
    size_t rem = src_num % 3;

    int16_t s0 = in[j];
    int16_t s1 = (j + 1 < in_count) ? in[j + 1] : in[in_count - 1];

    int32_t mixed = ((int32_t)(3 - rem) * (int32_t)s0) + ((int32_t)rem * (int32_t)s1);
    out[i] = (int16_t)(mixed / 3);
  }

  return out_count;
}

static void write_u16_le(FILE *f, uint16_t v) {
  uint8_t b[2] = {(uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF)};
  fwrite(b, 1, sizeof(b), f);
}

static void write_u32_le(FILE *f, uint32_t v) {
  uint8_t b[4] = {
      (uint8_t)(v & 0xFF),
      (uint8_t)((v >> 8) & 0xFF),
      (uint8_t)((v >> 16) & 0xFF),
      (uint8_t)((v >> 24) & 0xFF),
  };
  fwrite(b, 1, sizeof(b), f);
}

static int write_wav_16le_mono(const char *path, const int16_t *samples, size_t count,
                               uint32_t sample_rate) {
  FILE *f = fopen(path, "wb");
  if (f == NULL) {
    return 0;
  }

  uint32_t data_bytes = (uint32_t)(count * sizeof(int16_t));
  uint32_t riff_size = 36u + data_bytes;
  uint16_t channels = 1;
  uint16_t bits_per_sample = 16;
  uint16_t block_align = (uint16_t)(channels * (bits_per_sample / 8));
  uint32_t byte_rate = sample_rate * (uint32_t)block_align;

  fwrite("RIFF", 1, 4, f);
  write_u32_le(f, riff_size);
  fwrite("WAVE", 1, 4, f);

  fwrite("fmt ", 1, 4, f);
  write_u32_le(f, 16);
  write_u16_le(f, 1);
  write_u16_le(f, channels);
  write_u32_le(f, sample_rate);
  write_u32_le(f, byte_rate);
  write_u16_le(f, block_align);
  write_u16_le(f, bits_per_sample);

  fwrite("data", 1, 4, f);
  write_u32_le(f, data_bytes);

  if (count > 0) {
    fwrite(samples, sizeof(int16_t), count, f);
  }

  int ok = fflush(f) == 0;
  ok = ok && (fclose(f) == 0);
  return ok;
}

static size_t decode_with_jt9(const char *wav_path, decode_t *decodes, size_t max_decodes,
                              char *error_out, size_t error_out_len) {
  const char *jt9_bin = getenv("OPEN890_FT8_JT9_BIN");
  if (jt9_bin == NULL || jt9_bin[0] == '\0') {
    jt9_bin = "/usr/bin/jt9";
  }

  if (access(jt9_bin, X_OK) != 0) {
    snprintf(error_out, error_out_len, "jt9 not executable: %s", jt9_bin);
    return 0;
  }

  char cmd[1024];
  snprintf(cmd, sizeof(cmd), "%s -8 -p 15 -F 100 -L 200 -H 3600 '%s' 2>/dev/null", jt9_bin,
           wav_path);

  FILE *pipe = popen(cmd, "r");
  if (pipe == NULL) {
    snprintf(error_out, error_out_len, "failed to start jt9: %s", strerror(errno));
    return 0;
  }

  size_t count = 0;
  char line[1024];

  while (fgets(line, sizeof(line), pipe) != NULL) {
    if (line[0] == '\0' || line[0] == '\n' || line[0] == '<') {
      continue;
    }

    char utc[32] = {0};
    int snr = 0;
    float dt = 0.0f;
    float freq_hz = 0.0f;
    char marker[8] = {0};
    char text[MAX_MESSAGE_LEN + 1] = {0};

    int n = sscanf(line, " %31s %d %f %f %7s %255[^\n]", utc, &snr, &dt, &freq_hz, marker,
                   text);

    if (n < 6) {
      continue;
    }

    trim_right(text);
    if (text[0] == '\0') {
      continue;
    }

    if (count < max_decodes) {
      decodes[count].snr = snr;
      decodes[count].dt = dt;
      decodes[count].freq_hz = freq_hz;
      strncpy(decodes[count].text, text, MAX_MESSAGE_LEN);
      decodes[count].text[MAX_MESSAGE_LEN] = '\0';
      count++;
    }
  }

  int status = pclose(pipe);
  if (status == -1) {
    snprintf(error_out, error_out_len, "jt9 process error: %s", strerror(errno));
  } else if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    snprintf(error_out, error_out_len, "jt9 exited with status %d", WEXITSTATUS(status));
  } else if (count == 0) {
    error_out[0] = '\0';
  }

  return count;
}

static int build_json_response(const decode_t *decodes, size_t decode_count, const char *error,
                               sb_t *json) {
  if (!sb_init(json, 4096)) {
    return 0;
  }

  if (!sb_append(json, "{\"decodes\":[")) {
    return 0;
  }

  for (size_t i = 0; i < decode_count; i++) {
    if (i > 0 && !sb_append(json, ",")) {
      return 0;
    }

    if (!sb_appendf(json,
                    "{\"snr\":%d,\"dt\":%.1f,\"freq_hz\":%.1f,\"text\":",
                    decodes[i].snr, decodes[i].dt, decodes[i].freq_hz)) {
      return 0;
    }

    if (!sb_append_json_string(json, decodes[i].text)) {
      return 0;
    }

    if (!sb_append(json, "}")) {
      return 0;
    }
  }

  if (!sb_append(json, "]")) {
    return 0;
  }

  if (error != NULL && error[0] != '\0') {
    if (!sb_append(json, ",\"error\":")) {
      return 0;
    }

    if (!sb_append_json_string(json, error)) {
      return 0;
    }
  }

  if (!sb_append(json, "}")) {
    return 0;
  }

  return 1;
}

int main(void) {
  uint8_t lenbuf[4];
  uint8_t *packet = NULL;
  size_t packet_cap = 0;
  int16_t *samples_16k = NULL;
  size_t samples_16k_cap = 0;
  int16_t *samples_12k = NULL;
  size_t samples_12k_cap = 0;

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

    uint32_t seq = ((uint32_t)packet[0] << 24) | ((uint32_t)packet[1] << 16) |
                   ((uint32_t)packet[2] << 8) | (uint32_t)packet[3];

    size_t audio_len = (size_t)len - 4;
    size_t sample_count_16k = audio_len / 2;

    if (sample_count_16k > samples_16k_cap) {
      int16_t *next_samples = (int16_t *)realloc(samples_16k, sample_count_16k * sizeof(int16_t));
      if (next_samples == NULL) {
        break;
      }
      samples_16k = next_samples;
      samples_16k_cap = sample_count_16k;
    }

    for (size_t i = 0; i < sample_count_16k; i++) {
      samples_16k[i] = decode_i16_le(packet + 4 + (i * 2));
    }

    size_t sample_count_12k = (sample_count_16k * 3) / 4;
    if (sample_count_12k > samples_12k_cap) {
      int16_t *next_samples = (int16_t *)realloc(samples_12k, sample_count_12k * sizeof(int16_t));
      if (next_samples == NULL) {
        break;
      }
      samples_12k = next_samples;
      samples_12k_cap = sample_count_12k;
    }

    sample_count_12k = resample_16k_to_12k(samples_16k, sample_count_16k, samples_12k);

    char wav_path[256];
    snprintf(wav_path, sizeof(wav_path), "/tmp/open890_ft8_%ld_%u.wav", (long)getpid(), seq);

    char error_msg[256] = {0};
    decode_t decodes[MAX_DECODES];
    size_t decode_count = 0;

    if (!write_wav_16le_mono(wav_path, samples_12k, sample_count_12k, 12000)) {
      snprintf(error_msg, sizeof(error_msg), "failed to write wav");
    } else {
      decode_count = decode_with_jt9(wav_path, decodes, MAX_DECODES, error_msg, sizeof(error_msg));
    }

    unlink(wav_path);

    sb_t json;
    if (!build_json_response(decodes, decode_count, error_msg, &json)) {
      break;
    }

    uint32_t out_len = 4 + (uint32_t)json.len;
    uint8_t out_lenbuf[4] = {
        (uint8_t)((out_len >> 24) & 0xFF),
        (uint8_t)((out_len >> 16) & 0xFF),
        (uint8_t)((out_len >> 8) & 0xFF),
        (uint8_t)(out_len & 0xFF),
    };

    uint8_t seq_buf[4] = {
        (uint8_t)((seq >> 24) & 0xFF),
        (uint8_t)((seq >> 16) & 0xFF),
        (uint8_t)((seq >> 8) & 0xFF),
        (uint8_t)(seq & 0xFF),
    };

    int ok = 1;
    ok = ok && write_exact(out_lenbuf, sizeof(out_lenbuf));
    ok = ok && write_exact(seq_buf, sizeof(seq_buf));
    ok = ok && write_exact((const uint8_t *)json.buf, json.len);

    sb_free(&json);

    if (!ok) {
      break;
    }
  }

  free(packet);
  free(samples_16k);
  free(samples_12k);

  return 0;
}
