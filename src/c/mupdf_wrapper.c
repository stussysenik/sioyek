#include "mupdf_wrapper.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include <mupdf/fitz.h>
#include <mupdf/fitz/util.h>

struct SioyekMupdfDocument {
    fz_context *ctx;
    fz_document *doc;
};

struct TextBuilder {
    char *data;
    size_t len;
    size_t cap;
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

static int builder_reserve(struct TextBuilder *builder, size_t additional) {
    size_t required = builder->len + additional + 1;
    char *new_data = NULL;
    size_t new_cap = 0;

    if (required <= builder->cap) {
        return 1;
    }

    new_cap = builder->cap == 0 ? 256 : builder->cap;
    while (new_cap < required) {
        new_cap *= 2;
    }

    new_data = (char *)realloc(builder->data, new_cap);
    if (new_data == NULL) {
        return 0;
    }

    builder->data = new_data;
    builder->cap = new_cap;
    return 1;
}

static int builder_append_bytes(struct TextBuilder *builder, const char *bytes, size_t len) {
    if (!builder_reserve(builder, len)) {
        return 0;
    }

    memcpy(builder->data + builder->len, bytes, len);
    builder->len += len;
    builder->data[builder->len] = '\0';
    return 1;
}

static int builder_appendf(struct TextBuilder *builder, const char *fmt, ...) {
    va_list args;
    va_list args_copy;
    int needed = 0;

    va_start(args, fmt);
    va_copy(args_copy, args);
    needed = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);
    if (needed < 0) {
        va_end(args);
        return 0;
    }

    if (!builder_reserve(builder, (size_t)needed)) {
        va_end(args);
        return 0;
    }

    vsnprintf(builder->data + builder->len, builder->cap - builder->len, fmt, args);
    va_end(args);
    builder->len += (size_t)needed;
    return 1;
}

static int builder_append_outline(struct TextBuilder *builder, fz_context *ctx, fz_document *doc, fz_outline *outline, int depth) {
    fz_outline *node = outline;

    while (node != NULL) {
        int page_number = -1;
        int i = 0;

        if (node->page.chapter >= 0 && node->page.page >= 0) {
            page_number = fz_page_number_from_location(ctx, doc, node->page) + 1;
        }

        for (i = 0; i < depth; i++) {
            if (!builder_append_bytes(builder, "  ", 2)) {
                return 0;
            }
        }

        if (page_number > 0) {
            if (!builder_appendf(builder, "- %s @ page %d\n", node->title != NULL ? node->title : "(untitled)", page_number)) {
                return 0;
            }
        } else {
            if (!builder_appendf(builder, "- %s\n", node->title != NULL ? node->title : "(untitled)")) {
                return 0;
            }
        }

        if (node->down != NULL && !builder_append_outline(builder, ctx, doc, node->down, depth + 1)) {
            return 0;
        }
        node = node->next;
    }

    return 1;
}

static char *copy_buffer_string(fz_context *ctx, fz_buffer *buffer) {
    unsigned char *storage = NULL;
    size_t size = fz_buffer_storage(ctx, buffer, &storage);
    char *copy = (char *)malloc(size + 1);
    if (copy == NULL) {
        return NULL;
    }

    memcpy(copy, storage, size);
    copy[size] = '\0';
    return copy;
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

char *sioyek_mupdf_page_text(SioyekMupdfDocument *document, int page_index, char *error_message, size_t error_message_len) {
    fz_buffer *buffer = NULL;
    char *result = NULL;

    clear_error(error_message, error_message_len);

    if (document == NULL || document->ctx == NULL || document->doc == NULL) {
        write_error(error_message, error_message_len, "document is not open");
        return NULL;
    }

    fz_var(buffer);

    fz_try(document->ctx) {
        buffer = fz_new_buffer_from_page_number(document->ctx, document->doc, page_index, NULL);
        result = copy_buffer_string(document->ctx, buffer);
        if (result == NULL) {
            write_error(error_message, error_message_len, "failed to allocate page text");
        }
    }
    fz_always(document->ctx) {
        if (buffer != NULL) {
            fz_drop_buffer(document->ctx, buffer);
        }
    }
    fz_catch(document->ctx) {
        write_error(error_message, error_message_len, fz_caught_message(document->ctx));
        free(result);
        return NULL;
    }

    return result;
}

char *sioyek_mupdf_dump_outline(SioyekMupdfDocument *document, char *error_message, size_t error_message_len) {
    fz_outline *outline = NULL;
    struct TextBuilder builder = {0};

    clear_error(error_message, error_message_len);

    if (document == NULL || document->ctx == NULL || document->doc == NULL) {
        write_error(error_message, error_message_len, "document is not open");
        return NULL;
    }

    fz_var(outline);

    fz_try(document->ctx) {
        outline = fz_load_outline(document->ctx, document->doc);
        if (outline == NULL) {
            if (!builder_append_bytes(&builder, "(no outline)\n", strlen("(no outline)\n"))) {
                write_error(error_message, error_message_len, "failed to allocate outline buffer");
            }
        } else if (!builder_append_outline(&builder, document->ctx, document->doc, outline, 0)) {
            write_error(error_message, error_message_len, "failed to build outline text");
        }
    }
    fz_always(document->ctx) {
        if (outline != NULL) {
            fz_drop_outline(document->ctx, outline);
        }
    }
    fz_catch(document->ctx) {
        write_error(error_message, error_message_len, fz_caught_message(document->ctx));
        free(builder.data);
        return NULL;
    }

    if (builder.data == NULL) {
        return NULL;
    }

    return builder.data;
}

void sioyek_mupdf_free_string(char *value) {
    free(value);
}
