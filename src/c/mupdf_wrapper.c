#include "mupdf_wrapper.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mupdf/fitz.h>
#include <mupdf/fitz/util.h>

struct SioyekMupdfDocument {
    fz_context *ctx;
    fz_document *doc;
};

static void write_error(char *buffer, size_t buffer_len, const char *message) {
    if (buffer == NULL || buffer_len == 0) {
        return;
    }

    if (message == NULL || message[0] == '\0') {
        snprintf(buffer, buffer_len, "%s", "unknown MuPDF error");
        return;
    }

    snprintf(buffer, buffer_len, "%s", message);
}

static void clear_error(char *buffer, size_t buffer_len) {
    if (buffer != NULL && buffer_len > 0) {
        buffer[0] = '\0';
    }
}

SioyekMupdfDocument *sioyek_mupdf_open_document(const char *path, char *error_message, size_t error_message_len) {
    SioyekMupdfDocument *document = NULL;
    fz_context *ctx = NULL;
    fz_document *doc = NULL;

    clear_error(error_message, error_message_len);

    ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        write_error(error_message, error_message_len, "failed to allocate MuPDF context");
        return NULL;
    }

    fz_register_document_handlers(ctx);

    fz_try(ctx) {
        doc = fz_open_document(ctx, path);
    }
    fz_catch(ctx) {
        write_error(error_message, error_message_len, fz_caught_message(ctx));
        fz_drop_context(ctx);
        return NULL;
    }

    document = (SioyekMupdfDocument *)calloc(1, sizeof(*document));
    if (document == NULL) {
        write_error(error_message, error_message_len, "failed to allocate document wrapper");
        fz_drop_document(ctx, doc);
        fz_drop_context(ctx);
        return NULL;
    }

    document->ctx = ctx;
    document->doc = doc;
    return document;
}

void sioyek_mupdf_close_document(SioyekMupdfDocument *document) {
    if (document == NULL) {
        return;
    }

    if (document->ctx != NULL && document->doc != NULL) {
        fz_drop_document(document->ctx, document->doc);
    }
    if (document->ctx != NULL) {
        fz_drop_context(document->ctx);
    }

    free(document);
}

int sioyek_mupdf_page_count(SioyekMupdfDocument *document) {
    int page_count = 0;

    if (document == NULL || document->ctx == NULL || document->doc == NULL) {
        return 0;
    }

    fz_try(document->ctx) {
        page_count = fz_count_pages(document->ctx, document->doc);
    }
    fz_catch(document->ctx) {
        return 0;
    }

    return page_count;
}

int sioyek_mupdf_get_page_size(SioyekMupdfDocument *document, int page_index, float *page_width, float *page_height, char *error_message, size_t error_message_len) {
    fz_page *page = NULL;
    fz_rect bounds;

    clear_error(error_message, error_message_len);

    if (document == NULL || document->ctx == NULL || document->doc == NULL) {
        write_error(error_message, error_message_len, "document is not open");
        return 0;
    }

    fz_var(page);

    fz_try(document->ctx) {
        page = fz_load_page(document->ctx, document->doc, page_index);
        bounds = fz_bound_page(document->ctx, page);

        if (page_width != NULL) {
            *page_width = bounds.x1 - bounds.x0;
        }
        if (page_height != NULL) {
            *page_height = bounds.y1 - bounds.y0;
        }
    }
    fz_always(document->ctx) {
        if (page != NULL) {
            fz_drop_page(document->ctx, page);
        }
    }
    fz_catch(document->ctx) {
        write_error(error_message, error_message_len, fz_caught_message(document->ctx));
        return 0;
    }

    return 1;
}

SioyekRenderedPage sioyek_mupdf_render_page(SioyekMupdfDocument *document, int page_index, float scale, char *error_message, size_t error_message_len) {
    SioyekRenderedPage rendered = {0};
    fz_page *page = NULL;
    fz_pixmap *pixmap = NULL;
    fz_rect bounds;
    size_t pixel_bytes = 0;
    fz_matrix transform;

    clear_error(error_message, error_message_len);

    if (document == NULL || document->ctx == NULL || document->doc == NULL) {
        write_error(error_message, error_message_len, "document is not open");
        return rendered;
    }

    if (scale <= 0.0f) {
        write_error(error_message, error_message_len, "scale must be positive");
        return rendered;
    }

    fz_var(page);
    fz_var(pixmap);

    fz_try(document->ctx) {
        page = fz_load_page(document->ctx, document->doc, page_index);
        bounds = fz_bound_page(document->ctx, page);
        transform = fz_scale(scale, scale);
        pixmap = fz_new_pixmap_from_page(document->ctx, page, transform, fz_device_rgb(document->ctx), 0);

        rendered.width = fz_pixmap_width(document->ctx, pixmap);
        rendered.height = fz_pixmap_height(document->ctx, pixmap);
        rendered.stride = fz_pixmap_stride(document->ctx, pixmap);
        rendered.page_width = bounds.x1 - bounds.x0;
        rendered.page_height = bounds.y1 - bounds.y0;

        pixel_bytes = (size_t)rendered.stride * (size_t)rendered.height;
        rendered.pixels = (unsigned char *)malloc(pixel_bytes);
        if (rendered.pixels == NULL) {
            write_error(error_message, error_message_len, "failed to allocate rendered page buffer");
            memset(&rendered, 0, sizeof(rendered));
        } else {
            memcpy(rendered.pixels, fz_pixmap_samples(document->ctx, pixmap), pixel_bytes);
        }
    }
    fz_always(document->ctx) {
        if (pixmap != NULL) {
            fz_drop_pixmap(document->ctx, pixmap);
        }
        if (page != NULL) {
            fz_drop_page(document->ctx, page);
        }
    }
    fz_catch(document->ctx) {
        write_error(error_message, error_message_len, fz_caught_message(document->ctx));
        sioyek_mupdf_free_rendered_page(&rendered);
    }

    return rendered;
}

void sioyek_mupdf_free_rendered_page(SioyekRenderedPage *page) {
    if (page == NULL) {
        return;
    }

    free(page->pixels);
    page->pixels = NULL;
    page->width = 0;
    page->height = 0;
    page->stride = 0;
    page->page_width = 0;
    page->page_height = 0;
}
