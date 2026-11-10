extends RefCounted
## How big a save may be: one set of numbers for both the file reader (game/save_store.gd: how many bytes it reads) and
## the loading checks (sim/save_check.gd: how much soil it takes). Before v0.12.32 they were set apart - the reader 64 MB,
## the checks 16.5 million voxels - and a save holds ~13 bytes a voxel, so a nest past ~4 million voxels would have been
## saved and then not read (the bigger tank's soil held whole is 16.2 million).

const MAX_VOXELS := 16500000       # the bigger tank's soil held whole: 600 x 72 x 375 = 16.2 million (PART 0.12)
## bytes a voxel takes in a save: rho (1, PackedByteArray) + dug_at, dist, work_dist (4 each, PackedInt32Array)
const BYTES_PER_VOXEL := 13
## all the rest at its most: ants (MAX_ITEMS rows), brood, the pheromone grids, the journal (a colony of 1,000 is
## ~1-2 MB of it)
const MAX_REST := 96 * 1024 * 1024
## the unpacked save: anything longer is not one of ours, and is not read (a file can claim any length, and the reader
## would set that much memory aside first)
const MAX_RAW := MAX_VOXELS * BYTES_PER_VOXEL + MAX_REST
## the file on disk (packed: soil packs well, but a save of noise would not pack at all)
const MAX_FILE := MAX_RAW + 1024 * 1024
