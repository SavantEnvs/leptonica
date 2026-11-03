/* Known-answer probe: deterministic leptonica operations whose results test.sh asserts exactly. */
#include <stdio.h>
#include "allheaders.h"

int main(void)
{
    l_int32 w, h, d, count, ok = 1;
    PIX *pix1, *pix2, *pix3, *pix4;
    BOX *box;
    l_uint32 val;
    size_t size;
    l_uint8 *data;

    setLeptDebugOK(0);

    /* Read a committed fixture and report its geometry. */
    pix1 = pixRead("prog/weasel8.png");
    if (!pix1) return 2;
    pixGetDimensions(pix1, &w, &h, &d);
    printf("weasel8 %d %d %d\n", w, h, d);

    /* Binarize and count foreground pixels. */
    pix2 = pixThresholdToBinary(pix1, 128);
    pixCountPixels(pix2, &count, NULL);
    printf("weasel8-bin-fg %d\n", count);

    /* Render a filled box on a fresh 1 bpp image; count must equal the area. */
    pix3 = pixCreate(100, 80, 1);
    box = boxCreate(10, 20, 30, 40);
    pixRenderBox(pix3, box, 1, L_SET_PIXELS);
    pixCountPixels(pix3, &count, NULL);
    printf("box-outline %d\n", count);
    boxDestroy(&box);

    /* Rotate 90 degrees: dimensions swap. */
    pix4 = pixRotate90(pix3, 1);
    pixGetDimensions(pix4, &w, &h, NULL);
    printf("rot90 %d %d\n", w, h);
    pixDestroy(&pix4);

    /* PNG encode/decode roundtrip in memory preserves pixel content. */
    pixWriteMemPng(&data, &size, pix2, 0.0);
    pix4 = pixReadMemPng(data, size);
    pixEqual(pix2, pix4, &ok);
    printf("png-roundtrip %d\n", ok);
    lept_free(data);
    pixDestroy(&pix4);

    /* Scale down by 2 with area map; check a derived pixel sum. */
    pix4 = pixScale(pix1, 0.5, 0.5);
    pixGetDimensions(pix4, &w, &h, NULL);
    pixGetPixel(pix4, w / 2, h / 2, &val);
    printf("scaled %d %d %u\n", w, h, val);

    pixDestroy(&pix1);
    pixDestroy(&pix2);
    pixDestroy(&pix3);
    pixDestroy(&pix4);
    return 0;
}
