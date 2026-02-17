#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

int main(void) {
  uint8_t lenbuf[4];
  uint8_t *packet = NULL;
  size_t packet_cap = 0;

  while (1) {
    int rr = read_exact(lenbuf, sizeof(lenbuf));
    if (rr <= 0) {
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

    uint8_t seq_bytes[4] = {packet[0], packet[1], packet[2], packet[3]};
    const char *json = "{\"decodes\":[]}";
    uint32_t out_len = 4 + (uint32_t)strlen(json);
    uint8_t out_len_buf[4] = {(uint8_t)((out_len >> 24) & 0xFF),
                              (uint8_t)((out_len >> 16) & 0xFF),
                              (uint8_t)((out_len >> 8) & 0xFF),
                              (uint8_t)(out_len & 0xFF)};

    if (!write_exact(out_len_buf, sizeof(out_len_buf))) {
      break;
    }

    if (!write_exact(seq_bytes, sizeof(seq_bytes))) {
      break;
    }

    if (!write_exact((const uint8_t *)json, strlen(json))) {
      break;
    }
  }

  free(packet);
  return 0;
}
