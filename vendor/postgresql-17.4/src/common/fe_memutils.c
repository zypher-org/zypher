/*
 *	fe_memutils.c
 *		frontend memory management support
 *
 *	Copyright (c) 2003-2024, PostgreSQL Global Development Group
 *	src/common/fe_memutils.c
 */

#include "postgres_fe.h"
#include "common/fe_memutils.h"
#include <stdlib.h>
#include <string.h>

/*
 * Supply palloc and friends for frontend code that was written expecting
 * backend behavior.  We use plain malloc/free.  The "MCXT_ALLOC_NO_OOM"
 * flag lets the caller avoid an exit on OOM.
 */

void *
palloc(Size size)
{
	return pg_malloc(size);
}

void *
palloc0(Size size)
{
	return pg_malloc0(size);
}

void *
palloc_extended(Size size, int flags)
{
	return pg_malloc_extended(size, flags);
}

void *
repalloc(void *pointer, Size size)
{
	return pg_realloc(pointer, size);
}

void
pfree(void *pointer)
{
	pg_free(pointer);
}

char *
pstrdup(const char *in)
{
	return pg_strdup(in);
}

char *
pnstrdup(const char *in, Size size)
{
	char	   *result;
	Size		len;

	while (size > 0 && in[size - 1] == '\0')
		size--;

	len = strnlen(in, size);
	result = (char *) malloc(len + 1);
	if (result == NULL)
	{
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	memcpy(result, in, len);
	result[len] = '\0';
	return result;
}

void *
pg_malloc(size_t size)
{
	void	   *tmp;

	if (size == 0)
		size = 1;
	tmp = malloc(size);
	if (tmp == NULL)
	{
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	return tmp;
}

void *
pg_malloc0(size_t size)
{
	void	   *tmp;

	if (size == 0)
		size = 1;
	tmp = calloc(1, size);
	if (tmp == NULL)
	{
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	return tmp;
}

void *
pg_malloc_extended(size_t size, int flags)
{
	void	   *tmp;

	if (size == 0)
		size = 1;
	tmp = malloc(size);
	if (tmp == NULL)
	{
		if ((flags & MCXT_ALLOC_NO_OOM) != 0)
			return NULL;
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	if ((flags & MCXT_ALLOC_ZERO) != 0)
		memset(tmp, 0, size);
	return tmp;
}

void *
pg_realloc(void *ptr, size_t size)
{
	void	   *tmp;

	if (size == 0)
		size = 1;
	tmp = realloc(ptr, size);
	if (tmp == NULL)
	{
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	return tmp;
}

void
pg_free(void *ptr)
{
	free(ptr);
}

char *
pg_strdup(const char *in)
{
	char	   *tmp;

	if (in == NULL)
	{
		fprintf(stderr, "null pointer in pg_strdup\n");
		exit(EXIT_FAILURE);
	}
	tmp = strdup(in);
	if (tmp == NULL)
	{
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	return tmp;
}
