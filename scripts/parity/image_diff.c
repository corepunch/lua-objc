#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	CGImageRef image;
	uint8_t *pixels;
	size_t width;
	size_t height;
} DecodedImage;

static void release_image(DecodedImage *decoded) {
	if (decoded->pixels) free(decoded->pixels);
	if (decoded->image) CGImageRelease(decoded->image);
	memset(decoded, 0, sizeof(*decoded));
}

static int decode_image(const char *path, DecodedImage *decoded) {
	CFURLRef url = CFURLCreateFromFileSystemRepresentation(
		kCFAllocatorDefault, (const UInt8 *)path, (CFIndex)strlen(path), false);
	if (!url) return 0;
	CGImageSourceRef source = CGImageSourceCreateWithURL(url, NULL);
	CFRelease(url);
	if (!source) return 0;
	decoded->image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
	CFRelease(source);
	if (!decoded->image) return 0;
	decoded->width = CGImageGetWidth(decoded->image);
	decoded->height = CGImageGetHeight(decoded->image);
	if (decoded->width == 0 || decoded->height == 0 ||
		decoded->width > SIZE_MAX / 4 / decoded->height) return 0;
	size_t bytesPerRow = decoded->width * 4;
	decoded->pixels = calloc(decoded->height, bytesPerRow);
	if (!decoded->pixels) return 0;
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	if (!colorSpace) return 0;
	CGContextRef context = CGBitmapContextCreate(
		decoded->pixels, decoded->width, decoded->height, 8, bytesPerRow,
		colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(colorSpace);
	if (!context) return 0;
	CGContextSetBlendMode(context, kCGBlendModeCopy);
	CGContextDrawImage(context, CGRectMake(0, 0, decoded->width, decoded->height), decoded->image);
	CGContextRelease(context);
	return 1;
}

static int write_diff(const char *path, const uint8_t *pixels, size_t width, size_t height) {
	CFURLRef url = CFURLCreateFromFileSystemRepresentation(
		kCFAllocatorDefault, (const UInt8 *)path, (CFIndex)strlen(path), false);
	if (!url) return 0;
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, width * height * 4, NULL);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGImageRef image = provider && colorSpace ? CGImageCreate(
		width, height, 8, 32, width * 4, colorSpace,
		kCGImageAlphaLast | kCGBitmapByteOrder32Big, provider, NULL, false,
		kCGRenderingIntentDefault) : NULL;
	CGImageDestinationRef destination = image ? CGImageDestinationCreateWithURL(
		url, CFSTR("public.png"), 1, NULL) : NULL;
	int ok = destination != NULL;
	if (destination) {
		CGImageDestinationAddImage(destination, image, NULL);
		ok = CGImageDestinationFinalize(destination);
		CFRelease(destination);
	}
	if (image) CGImageRelease(image);
	if (colorSpace) CGColorSpaceRelease(colorSpace);
	if (provider) CGDataProviderRelease(provider);
	CFRelease(url);
	return ok;
}

static void print_usage(const char *program) {
	fprintf(stderr, "usage: %s REFERENCE.png CANDIDATE.png [--diff OUTPUT.png]\n", program);
}

int main(int argc, char **argv) {
	if (argc != 3 && argc != 5) {
		print_usage(argv[0]);
		return 2;
	}
	const char *diffPath = NULL;
	if (argc == 5) {
		if (strcmp(argv[3], "--diff") != 0) {
			print_usage(argv[0]);
			return 2;
		}
		diffPath = argv[4];
	}
	DecodedImage reference = {0}, candidate = {0};
	if (!decode_image(argv[1], &reference)) {
		fprintf(stderr, "cannot decode reference PNG: %s\n", argv[1]);
		release_image(&reference);
		return 2;
	}
	if (!decode_image(argv[2], &candidate)) {
		fprintf(stderr, "cannot decode candidate PNG: %s\n", argv[2]);
		release_image(&reference);
		release_image(&candidate);
		return 2;
	}
	if (reference.width != candidate.width || reference.height != candidate.height) {
		printf("{\"status\":\"different-size\",\"referenceWidth\":%zu,\"referenceHeight\":%zu,"
			"\"candidateWidth\":%zu,\"candidateHeight\":%zu}\n",
			reference.width, reference.height, candidate.width, candidate.height);
		release_image(&reference);
		release_image(&candidate);
		return 0;
	}
	size_t pixelCount = reference.width * reference.height;
	size_t differentPixels = 0, differentChannels = 0;
	unsigned int maxChannelDifference = 0;
	uint64_t totalChannelDifference = 0;
	uint8_t *diffPixels = diffPath ? calloc(pixelCount, 4) : NULL;
	if (diffPath && !diffPixels) {
		fprintf(stderr, "cannot allocate diff image\n");
		release_image(&reference);
		release_image(&candidate);
		return 2;
	}
	for (size_t i = 0; i < pixelCount; i++) {
		int pixelDiffers = 0;
		unsigned int pixelMaximum = 0;
		for (size_t channel = 0; channel < 4; channel++) {
			int delta = (int)reference.pixels[i * 4 + channel] -
				(int)candidate.pixels[i * 4 + channel];
			unsigned int absolute = (unsigned int)(delta < 0 ? -delta : delta);
			if (absolute) {
				pixelDiffers = 1;
				differentChannels++;
				totalChannelDifference += absolute;
				if (absolute > maxChannelDifference) maxChannelDifference = absolute;
				if (absolute > pixelMaximum) pixelMaximum = absolute;
			}
		}
		if (pixelDiffers) {
			differentPixels++;
			if (diffPixels) {
				diffPixels[i * 4] = 255;
				diffPixels[i * 4 + 1] = pixelMaximum > 96 ? 32 : 0;
				diffPixels[i * 4 + 2] = 0;
				diffPixels[i * 4 + 3] = 255;
			}
		}
	}
	int diffWritten = !diffPath || write_diff(diffPath, diffPixels, reference.width, reference.height);
	if (!diffWritten) fprintf(stderr, "cannot write diff PNG: %s\n", diffPath);
	double meanAbsoluteError = pixelCount ? (double)totalChannelDifference / (double)(pixelCount * 4) : 0;
	double percent = pixelCount ? 100.0 * (double)differentPixels / (double)pixelCount : 0;
	printf("{\"status\":\"%s\",\"width\":%zu,\"height\":%zu,\"totalPixels\":%zu,"
		"\"differentPixels\":%zu,\"differentPixelPercent\":%.8f,"
		"\"differentChannels\":%zu,\"meanAbsoluteError\":%.8f,"
		"\"maxChannelDifference\":%u}\n",
		differentPixels ? "different" : "identical", reference.width, reference.height,
		pixelCount, differentPixels, percent, differentChannels, meanAbsoluteError,
		maxChannelDifference);
	free(diffPixels);
	release_image(&reference);
	release_image(&candidate);
	return diffWritten ? 0 : 2;
}
