#include <stdio.h>
#include <stdlib.h>
#include <libfdt.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <endian.h>
#include <stdint.h>

#define FIT_IMAGES_PATH		"/images"

/* image node */
#define FIT_DATA_PROP		"data"
#define FIT_DATA_POSITION_PROP	"data-position"
#define FIT_DATA_OFFSET_PROP	"data-offset"
#define FIT_DATA_SIZE_PROP	"data-size"
#define FIT_ARCH_PROP		"arch"
#define FIT_TYPE_PROP		"type"
#define FIT_DESC_PROP		"description"

int write_file(const char *image_name, void const *image_data, const uint32_t image_len)
{
	int ofd;

	ofd = open(image_name, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (ofd == -1)
		return errno;

	printf("writing file %s (%d bytes)\n", image_name, image_len);
	if (write(ofd, image_data, image_len) != image_len) {
		close(ofd);
		return errno;
	}

	close(ofd);
	return 0;
}

int main(int argc, char *argv[])
{
	int fd;
	struct stat st;
	void *fit;
	int ret;
	uint32_t fitsize;
	int node, images;
	int image_description_len, image_name_len, image_data_len, image_type_len;
	const char *image_name, *image_type, *image_description;
	const uint32_t *image_offset_be, *image_pos_be, *image_len_be;
	uint32_t image_offset, image_pos, image_len;
	char *get_name = NULL;
	void const *image_data;

	if (argc < 2)
		return EINVAL;

	if (argc >= 3)
		get_name = argv[2];

	fd = open(argv[1], O_RDONLY, 0);
	if (fd == -1)
		return errno;

	if (fstat(fd, &st) == -1) {
		ret=errno;
		goto closefd;
	}

	fit = mmap(0, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (fit == MAP_FAILED) {
		ret=errno;
		goto closefd;
	}

	ret = fdt_check_header(fit);
	if (ret)
		goto unmapfd;

	fitsize = fdt_totalsize(fit);
	if (fitsize > st.st_size) {
		ret = -EFBIG;
		goto unmapfd;
	}

	printf("got fit size %u bytes\n", fitsize);

	images = fdt_path_offset(fit, FIT_IMAGES_PATH);
	if (images < 0) {
		printf("FIT: Cannot find %s node: %d\n", FIT_IMAGES_PATH, images);
		ret = -EINVAL;
		goto unmapfd;
	}

	fdt_for_each_subnode(node, fit, images) {
		image_name = fdt_get_name(fit, node, &image_name_len);
		image_type = fdt_getprop(fit, node, FIT_TYPE_PROP, &image_type_len);
		image_offset_be = fdt_getprop(fit, node, FIT_DATA_OFFSET_PROP, NULL);
		image_pos_be = fdt_getprop(fit, node, FIT_DATA_POSITION_PROP, NULL);
		image_len_be = fdt_getprop(fit, node, FIT_DATA_SIZE_PROP, NULL);
		image_data = fdt_getprop(fit, node, FIT_DATA_PROP, &image_data_len);

		if (!image_name || !image_type)
			continue;

		if (image_len_be)
			image_len = fdt32_to_cpu(*image_len_be);
		else if (image_data)
			image_len = image_data_len;
		else
			continue;

		if (!image_data) {
			if (image_offset_be)
				image_data = fit + fdt32_to_cpu(*image_offset_be) + fitsize;
			else if (image_pos_be)
				image_data = fit + fdt32_to_cpu(*image_pos_be);
			else
				continue;
		};

		image_description = fdt_getprop(fit, node, FIT_DESC_PROP, &image_description_len);
		if (!get_name || (get_name && !strncmp(get_name, image_name, image_name_len)))
			write_file(image_name, image_data, image_len);

		printf("FIT: %16s sub-image 0x%08x - 0x%08x '%s' %s%s%s\n",
			image_type, image_data - fit, image_data + image_len - fit, image_name,
			image_description?"(":"", image_description?:"", image_description?") ":"");
	}

unmapfd:
	munmap(fit, st.st_size);
closefd:
	close(fd);

	return ret;
}
