#ifndef SIOYEK_MUPDF_WRAPPER_H
#define SIOYEK_MUPDF_WRAPPER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SioyekMupdfDocument SioyekMupdfDocument;

typedef struct SioyekRenderedPage {
    unsigned char *pixels;
    int width;
    int height;
    int stride;
    float page_width;
    float page_height;
} SioyekRenderedPage;

SioyekMupdfDocument *sioyek_mupdf_open_document(const char *path, char *error_message, size_t error_message_len);
void sioyek_mupdf_close_document(SioyekMupdfDocument *document);
int sioyek_mupdf_page_count(SioyekMupdfDocument *document);
int sioyek_mupdf_get_page_size(SioyekMupdfDocument *document, int page_index, float *page_width, float *page_height, char *error_message, size_t error_message_len);
SioyekRenderedPage sioyek_mupdf_render_page(SioyekMupdfDocument *document, int page_index, float scale, char *error_message, size_t error_message_len);
void sioyek_mupdf_free_rendered_page(SioyekRenderedPage *page);

#ifdef __cplusplus
}
#endif

#endif
