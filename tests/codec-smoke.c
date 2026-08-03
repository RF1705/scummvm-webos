#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mad.h>
#include <mpeg2dec/mpeg2.h>
#include <ogg/ogg.h>
#include <theora/theoradec.h>

static unsigned char *read_file(const char *path, size_t extra, size_t *size_out) {
    FILE *file = fopen(path, "rb");
    long length;
    unsigned char *data;

    if (!file) {
        fprintf(stderr, "Cannot open %s: %s\n", path, strerror(errno));
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "Cannot determine size of %s\n", path);
        fclose(file);
        return NULL;
    }

    data = (unsigned char *)calloc((size_t)length + extra, 1);
    if (!data) {
        fprintf(stderr, "Out of memory reading %s\n", path);
        fclose(file);
        return NULL;
    }
    if (fread(data, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "Cannot read %s\n", path);
        free(data);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *size_out = (size_t)length;
    return data;
}

static int test_mp3(const char *path) {
    size_t size = 0;
    unsigned char *data = read_file(path, MAD_BUFFER_GUARD, &size);
    struct mad_stream stream;
    struct mad_frame frame;
    struct mad_synth synth;
    unsigned int attempts = 0;
    int decoded = 0;

    if (!data)
        return 1;

    mad_stream_init(&stream);
    mad_frame_init(&frame);
    mad_synth_init(&synth);
    mad_stream_buffer(&stream, data, (unsigned long)(size + MAD_BUFFER_GUARD));

    while (attempts++ < 4096) {
        if (mad_frame_decode(&frame, &stream) == 0) {
            mad_synth_frame(&synth, &frame);
            if (synth.pcm.length > 0 && synth.pcm.channels > 0) {
                decoded = 1;
                break;
            }
            continue;
        }
        if (stream.error == MAD_ERROR_BUFLEN)
            break;
        if (!MAD_RECOVERABLE(stream.error)) {
            fprintf(stderr, "libmad failed for %s: %s\n", path,
                    mad_stream_errorstr(&stream));
            break;
        }
    }

    mad_synth_finish(&synth);
    mad_frame_finish(&frame);
    mad_stream_finish(&stream);
    free(data);

    if (!decoded) {
        fprintf(stderr, "No MP3 audio frame decoded from %s\n", path);
        return 1;
    }
    puts("MP3/libmad: decoded audio frame");
    return 0;
}

static int test_mpeg2(const char *path) {
    FILE *file = fopen(path, "rb");
    mpeg2dec_t *decoder;
    unsigned char buffer[4096];
    size_t count;
    int saw_sequence = 0;
    int saw_slice = 0;

    if (!file) {
        fprintf(stderr, "Cannot open %s: %s\n", path, strerror(errno));
        return 1;
    }
    decoder = mpeg2_init();
    if (!decoder) {
        fprintf(stderr, "mpeg2_init failed\n");
        fclose(file);
        return 1;
    }

    while ((count = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        mpeg2_state_t state;
        mpeg2_buffer(decoder, buffer, buffer + count);
        while ((state = mpeg2_parse(decoder)) != STATE_BUFFER) {
            if (state == STATE_SEQUENCE)
                saw_sequence = 1;
            if (state == STATE_SLICE || state == STATE_END)
                saw_slice = 1;
            if (state == STATE_INVALID) {
                fprintf(stderr, "libmpeg2 rejected %s\n", path);
                mpeg2_close(decoder);
                fclose(file);
                return 1;
            }
        }
    }

    mpeg2_close(decoder);
    fclose(file);
    if (!saw_sequence || !saw_slice) {
        fprintf(stderr, "No complete MPEG-2 sequence/frame decoded from %s\n", path);
        return 1;
    }
    puts("MPEG-2/libmpeg2: decoded video frame");
    return 0;
}

static int decode_theora_packet(th_dec_ctx *decoder, ogg_packet *packet) {
    ogg_int64_t granule = 0;
    th_ycbcr_buffer image;
    int result = th_decode_packetin(decoder, packet, &granule);

    if (result == TH_DUPFRAME)
        return 0;
    if (result != 0) {
        fprintf(stderr, "Theora packet decode failed: %d\n", result);
        return -1;
    }
    if (th_decode_ycbcr_out(decoder, image) != 0 ||
        image[0].width <= 0 || image[0].height <= 0) {
        fprintf(stderr, "Theora decoder returned no image\n");
        return -1;
    }
    return 1;
}

static int test_theora(const char *path) {
    FILE *file = fopen(path, "rb");
    ogg_sync_state sync;
    ogg_stream_state stream;
    ogg_page page;
    ogg_packet packet;
    th_info info;
    th_comment comment;
    th_setup_info *setup = NULL;
    th_dec_ctx *decoder = NULL;
    int stream_ready = 0;
    int headers = 0;
    int decoded = 0;

    if (!file) {
        fprintf(stderr, "Cannot open %s: %s\n", path, strerror(errno));
        return 1;
    }

    ogg_sync_init(&sync);
    th_info_init(&info);
    th_comment_init(&comment);

    while (!decoded) {
        char *input = ogg_sync_buffer(&sync, 4096);
        size_t bytes = fread(input, 1, 4096, file);
        if (ogg_sync_wrote(&sync, (long)bytes) != 0) {
            fprintf(stderr, "ogg_sync_wrote failed\n");
            break;
        }

        while (ogg_sync_pageout(&sync, &page) == 1 && !decoded) {
            if (!stream_ready) {
                if (ogg_stream_init(&stream, ogg_page_serialno(&page)) != 0) {
                    fprintf(stderr, "ogg_stream_init failed\n");
                    goto cleanup;
                }
                stream_ready = 1;
            }
            if (ogg_page_serialno(&page) != stream.serialno)
                continue;
            if (ogg_stream_pagein(&stream, &page) != 0) {
                fprintf(stderr, "ogg_stream_pagein failed\n");
                goto cleanup;
            }

            while (ogg_stream_packetout(&stream, &packet) == 1 && !decoded) {
                if (headers < 3) {
                    int result = th_decode_headerin(&info, &comment, &setup, &packet);
                    if (result <= 0) {
                        fprintf(stderr, "Invalid Theora header in %s: %d\n", path, result);
                        goto cleanup;
                    }
                    headers++;
                    if (headers == 3) {
                        decoder = th_decode_alloc(&info, setup);
                        if (!decoder) {
                            fprintf(stderr, "th_decode_alloc failed\n");
                            goto cleanup;
                        }
                    }
                } else {
                    int result = decode_theora_packet(decoder, &packet);
                    if (result < 0)
                        goto cleanup;
                    decoded = result;
                }
            }
        }
        if (bytes == 0)
            break;
    }

cleanup:
    if (decoder)
        th_decode_free(decoder);
    if (setup)
        th_setup_free(setup);
    th_comment_clear(&comment);
    th_info_clear(&info);
    if (stream_ready)
        ogg_stream_clear(&stream);
    ogg_sync_clear(&sync);
    fclose(file);

    if (!decoded) {
        fprintf(stderr, "No Theora video frame decoded from %s\n", path);
        return 1;
    }
    puts("Theora/libtheoradec: decoded video frame");
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s TEST.mp3 TEST.m2v TEST.ogv\n", argv[0]);
        return 2;
    }
    if (test_mp3(argv[1]) != 0)
        return 1;
    if (test_mpeg2(argv[2]) != 0)
        return 1;
    if (test_theora(argv[3]) != 0)
        return 1;
    puts("All target codec smoke tests passed.");
    return 0;
}
