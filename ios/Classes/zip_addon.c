
extern int zip_set_compression_level(struct zip_t *zip, int level) {
    int old_level = zip->level;
    zip->level = level;
    return old_level;
}
