#import "SGAudioSourceQueue.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#include <string.h>
#include <stdbool.h>

static uintptr_t sg_sourceImage;
static bool sg_sourceLayout;
static bool readWord(uintptr_t address, uint64_t *value) {
    vm_size_t count = 0;
    *value = 0;
    return address && address <= UINTPTR_MAX - sizeof *value &&
        vm_read_overwrite(mach_task_self(), address, sizeof *value, (vm_address_t)value, &count) == KERN_SUCCESS && count == sizeof *value;
}
void SGAudioSourceQueueInitialize(void) {
    // Spotify 9.1.78 arm64. A version string alone cannot establish the private queue ABI.
    static const unsigned char uuid[16] = {0xc7,0x12,0x37,0x0b,0x44,0xcd,0x35,0xc8,0xa0,0x58,0x4f,0xbe,0xd1,0xad,0x07,0x58};
    const struct mach_header_64 *header = (const void *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64) return;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command) &&
            !memcmp(((const struct uuid_command *)command)->uuid, uuid, sizeof uuid)) {
            sg_sourceImage = (uintptr_t)header;
            sg_sourceLayout = true;
            return;
        }
    }
}
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback) {
    uint64_t instruction;
    return sg_sourceLayout && (uintptr_t)callback.inputProc == sg_sourceImage + 0x24dd98 &&
        readWord((uintptr_t)callback.inputProc, &instruction) && instruction == UINT64_C(0xa9bc5ff8350005a3);
}
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames) {
    if (!maximumFrames || !SGAudioSourceQueueSupported(callback)) return 0;
    uintptr_t context = (uintptr_t)callback.inputProcRefCon;
    uint64_t instruction, sink, table, function, delegate, channels, begin, end;
    if (!context || context > UINTPTR_MAX - 0x90 ||
        !readWord((uintptr_t)callback.inputProc, &instruction) || instruction != UINT64_C(0xa9bc5ff8350005a3) ||
        !readWord(context + 0x78, &sink) || !sink || sink > UINTPTR_MAX - 0x28 ||
        !readWord(sink, &table) || table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x180f3c ||
        !readWord(function, &instruction) || instruction != UINT64_C(0xa9025ff8d10183ff) ||
        !readWord(sink + 0x20, &delegate) || delegate < 8 || delegate > UINTPTR_MAX - 0xb8 ||
        !readWord(delegate, &table) || table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x10908b4 ||
        !readWord(function, &instruction) || instruction != UINT64_C(0x17c2d2c2d1002000) ||
        !readWord(sg_sourceImage + 0x1453c0, &instruction) || instruction != UINT64_C(0xa9016ffcd101c3ff) ||
        !readWord(context + 0x6c, &channels) || (uint32_t)channels != 2 ||
        !readWord(context + 0x80, &begin) || !readWord(context + 0x88, &end) || end <= begin) return 0;
    uintptr_t owner = delegate - 8;
    uint64_t head, tail, pending;
    // The reader at 0x1453c0 processes pending commands before consuming its queue.
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &head) || !readWord(owner + 0x20, &tail)) return 0;
    uint64_t cursor = head, samples = 0;
    uintptr_t visited[128];
    unsigned count = 0;
    while (cursor != tail) {
        if (count == 128 || !cursor || cursor > UINTPTR_MAX - 0x28) return 0;
        for (unsigned i = 0; i < count; i++) if (visited[i] == cursor) return 0;
        visited[count++] = cursor;
        uint64_t block, remaining, next;
        if (!readWord(cursor, &block) || !readWord(cursor + 0x20, &next)) return 0;
        if (next != tail) for (unsigned i = 0; i < count; i++) if (visited[i] == next) return 0;
        if (!block) break; // End-of-track/event nodes fence the following track's PCM.
        if (block > UINTPTR_MAX - 0x28 || !readWord(block + 0x20, &remaining) ||
            remaining > 882000 || (remaining & 1)) return 0;
        // An exact-sized pull leaves the exhausted block at the head. The verified
        // reader (0x145550–0x1455c8) pops it on the next pull and continues with the
        // following block. Only a null block is an event fence; zero samples are not.
        samples += remaining;
        if (samples / 2 >= maximumFrames) break;
        cursor = next;
    }
    uint64_t headAfter, tailAfter;
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &headAfter) || !readWord(owner + 0x20, &tailAfter) ||
        head != headAfter || tail != tailAfter) return 0;
    // Unvisited nodes cannot affect this prefix. Pending commands and an unstable queue
    // still invalidate the snapshot even when enough frames were found in its first node.
    return (UInt32)MIN(samples / 2, maximumFrames);
}
