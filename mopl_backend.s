// =====================================================================
// MOPL# Interpreter — ARM64 Assembly (Apple Silicon / macOS)
// =====================================================================
// Implements:
//   - File I/O (open/read/close a .mopl script passed as argv[1])
//   - Lexer/line-scanner (splits the script into lines, trims whitespace)
//   - Tag table (linked list) storing name/type/value/assignment-level
//   - Tag.[name] = [type].[value]        (declaration)
//   - Tag.[name] += / ++= ...            (reassignment, "+" count law)
//   - Terminal '[name]'                  (stdout)
//   - Op of a add b ==  / subtract / times / divide   (num math)
//   - Dif in [name],[name],...           (introspection dump)
//
// NOT implemented in this pass (left as extension points, see NOTES.md):
//   - logic tags / EndLogic execution
//   - Check/EndCheck, Cycle/EndCycle control flow
//   - Window / In / At GUI + Cocoa objc_msgSend bridge
//
// Build (on a real Mac with Xcode command line tools):
//   as -o mopl.o mopl_backend.s
//   ld -o mopl mopl.o -lSystem -syslibroot `xcrun -sdk macosx --show-sdk-path`
//   ./mopl script.mopl
// =====================================================================

.global _main
.align 2

// ---------------------------------------------------------------
// Syscall numbers (macOS BSD syscalls, class 0x2000000)
// ---------------------------------------------------------------
.equ SYS_EXIT,  0x2000001
.equ SYS_READ,  0x2000003
.equ SYS_WRITE, 0x2000004
.equ SYS_OPEN,  0x2000005
.equ SYS_CLOSE, 0x2000006

.equ O_RDONLY,  0x0000

.equ TAG_NUM,   0
.equ TAG_STATE, 1
.equ TAG_BLEA,  2
.equ TAG_LOGIC, 3

// Tag record layout (fixed-size slots, simplest possible linked list node):
//   offset 0  : next ptr           (8 bytes)
//   offset 8  : name ptr           (8 bytes)  -> NUL-terminated string
//   offset 16 : type               (8 bytes)  -> TAG_NUM / TAG_STATE / TAG_BLEA / TAG_LOGIC
//   offset 24 : value (int)        (8 bytes)  -> numeric/bool value
//   offset 32 : value (str ptr)    (8 bytes)  -> used when type == TAG_BLEA
//   offset 40 : assignment level   (8 bytes)  -> count of '+' seen on last write
.equ TAG_SIZE, 48

// =================================================================
// .bss — runtime buffers
// =================================================================
.bss
.align 4
file_buf:       .skip 65536      // raw contents of the .mopl script
line_buf:       .skip 1024       // current line, NUL-terminated
tok_buf:        .skip 256        // scratch token buffer
num_str_buf:    .skip 32         // scratch buffer for itoa output
tag_name_buf:   .skip 128        // scratch buffer for a parsed tag name

tag_list_head:  .skip 8          // pointer to first Tag record (0 = empty)
file_fd:        .skip 8          // fd of opened script
file_len:       .skip 8          // bytes actually read into file_buf

// =================================================================
// .data — constants / literal strings
// =================================================================
.data
.align 4
str_true:       .asciz "true"
str_false:      .asciz "false"
str_prefix_tag: .asciz "Tag."
str_terminal:   .asciz "Terminal"
str_op_of:      .asciz "Op of"
str_dif_in:     .asciz "Dif in"
str_num:        .asciz "num."
str_state:      .asciz "state."
str_blea:       .asciz "blea."
newline:        .asciz "\n"
err_usage:      .asciz "usage: mopl run <file>.mopl\n"
err_open:       .asciz "error: could not open script\n"

// =================================================================
// .text — MODULE 1: entry point, argv parsing, file I/O, line loop
// =================================================================
.text

// -----------------------------------------------------------------
// _main(argc: x0, argv: x1)
//   argv[0] = program name
//   argv[1] = path to .mopl script
// -----------------------------------------------------------------
_main:
    // Save argc/argv (we only need argv[1])
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

cmp     x0, #3
    b.lt    .Lusage_error

    // x1 = argv, load argv[2] (the script path, after "run") into x2
    ldr     x2, [x1, #16]        // x2 = argv[2]

    // ---- open(path, O_RDONLY, 0) ----
    mov     x0, x2               // path
    mov     x1, #O_RDONLY        // flags
    mov     x2, #0               // mode (unused for read)
    movz    x16, #0x0005
    movk    x16, #0x0200, lsl #16
    svc     #0
    b.cs    .Lopen_error         // carry set => syscall error
    adrp    x9, file_fd@PAGE
    add     x9, x9, file_fd@PAGEOFF
    str     x0, [x9]             // save fd

    // ---- read(fd, file_buf, 65536) ----
    mov     x19, x0              // x19 = fd (callee-saved)
    adrp    x1, file_buf@PAGE
    add     x1, x1, file_buf@PAGEOFF
    mov     x0, x19
    mov     x2, #65536
    movz    x16, #0x0003
    movk    x16, #0x0200, lsl #16
    svc     #0
    b.cs    .Lopen_error
    adrp    x9, file_len@PAGE
    add     x9, x9, file_len@PAGEOFF
    str     x0, [x9]             // save number of bytes read

    // ---- close(fd) ----
    mov     x0, x19
    movz    x16, #0x0006
    movk    x16, #0x0200, lsl #16
    svc     #0

    // NUL-terminate the buffer at file_buf[file_len]
    adrp    x9, file_buf@PAGE
    add     x9, x9, file_buf@PAGEOFF
    adrp    x10, file_len@PAGE
    add     x10, x10, file_len@PAGEOFF
    ldr     x11, [x10]
    add     x12, x9, x11
    strb    wzr, [x12]

    // ---- hand the buffer to the line-scanner / dispatcher ----
    mov     x0, x9                // x0 = pointer to script text
    bl      _run_script

    mov     x0, #0
    b       .Lexit

.Lusage_error:
    adrp    x1, err_usage@PAGE
    add     x1, x1, err_usage@PAGEOFF
    bl      _print_cstr
    mov     x0, #1
    b       .Lexit

.Lopen_error:
    adrp    x1, err_open@PAGE
    add     x1, x1, err_open@PAGEOFF
    bl      _print_cstr
    mov     x0, #1
    b       .Lexit

.Lexit:
    movz    x16, #0x0001
    movk    x16, #0x0200, lsl #16   
    svc     #0

// -----------------------------------------------------------------
// _run_script(x0 = pointer to NUL-terminated script text)
//   Splits the buffer into lines on '\n', trims leading spaces,
//   and dispatches each non-empty line to _dispatch_line.
//   Blank lines and lines inside GUI/logic/check/cycle blocks are
//   currently just skipped by the dispatcher (see NOTES.md).
// -----------------------------------------------------------------
_run_script:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0               // x19 = cursor into script text

.Lline_loop:
    ldrb    w2, [x19]
    cbz     w2, .Lrun_done         // hit final NUL -> done

    // copy characters up to '\n' or NUL into line_buf
    adrp    x3, line_buf@PAGE
    add     x3, x3, line_buf@PAGEOFF
    mov     x4, x3                 // x4 = write cursor
.Lcopy_char:
    ldrb    w2, [x19]
    cbz     w2, .Lline_ready        // NUL -> line ready (last line, no \n)
    cmp     w2, #10                 // '\n'
    b.eq    .Lnewline_hit
    strb    w2, [x4], #1
    add     x19, x19, #1
    b       .Lcopy_char
.Lnewline_hit:
    add     x19, x19, #1            // consume the '\n'
.Lline_ready:
    strb    wzr, [x4]               // NUL-terminate line_buf

    mov     x0, x3
    bl      _dispatch_line
    b       .Lline_loop

.Lrun_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// -----------------------------------------------------------------
// _dispatch_line(x0 = pointer to trimmed, NUL-terminated line)
//   Looks at the line's leading keyword and routes it to the
//   right handler. Unrecognized / not-yet-implemented lines
//   (logic/check/cycle/window/etc.) are silently skipped for now.
// -----------------------------------------------------------------
_dispatch_line:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x9, x0                 // x9 = line pointer

    // skip leading spaces/tabs
.Lskip_ws:
    ldrb    w10, [x9]
    cmp     w10, #' '
    b.eq    .Ladv_ws
    cmp     w10, #9                // tab
    b.eq    .Ladv_ws
    b       .Lws_done
.Ladv_ws:
    add     x9, x9, #1
    b       .Lskip_ws
.Lws_done:

    ldrb    w10, [x9]
    cbz     w10, .Ldispatch_done   // empty line -> nothing to do

    // "Tag." prefix?
    adrp    x1, str_prefix_tag@PAGE
    add     x1, x1, str_prefix_tag@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Ltry_terminal
    mov     x0, x9
    bl      _handle_tag_line
    b       .Ldispatch_done

.Ltry_terminal:
    adrp    x1, str_terminal@PAGE
    add     x1, x1, str_terminal@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Ltry_op
    mov     x0, x9
    bl      _handle_terminal_line
    b       .Ldispatch_done

.Ltry_op:
    adrp    x1, str_op_of@PAGE
    add     x1, x1, str_op_of@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Ltry_dif
    mov     x0, x9
    bl      _handle_op_line
    b       .Ldispatch_done

.Ltry_dif:
    adrp    x1, str_dif_in@PAGE
    add     x1, x1, str_dif_in@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Ldispatch_done     // unrecognized keyword: logic/check/cycle/window/etc — skip
    mov     x0, x9
    bl      _handle_dif_line

.Ldispatch_done:
    ldp     x29, x30, [sp], #16
    ret

// =================================================================
// MODULE 2: helper utilities (string compare, itoa, tag lookup/create)
// =================================================================

// -----------------------------------------------------------------
// _starts_with(x0 = haystack, x1 = needle) -> x0 = 1 if haystack
// starts with needle, else 0. Both NUL-terminated.
// -----------------------------------------------------------------
_starts_with:
    mov     x2, x0
    mov     x3, x1
.Lsw_loop:
    ldrb    w4, [x3]
    cbz     w4, .Lsw_match          // consumed all of needle -> match
    ldrb    w5, [x2]
    cmp     w4, w5
    b.ne    .Lsw_nomatch
    add     x2, x2, #1
    add     x3, x3, #1
    b       .Lsw_loop
.Lsw_match:
    mov     x0, #1
    ret
.Lsw_nomatch:
    mov     x0, #0
    ret

// -----------------------------------------------------------------
// _print_cstr(x0 = pointer to NUL-terminated string) -> writes to stdout
// -----------------------------------------------------------------
_print_cstr:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x1, x0                  // buf
    mov     x2, #0                  // length accumulator
.Lpc_len:
    ldrb    w3, [x1, x2]
    cbz     w3, .Lpc_go
    add     x2, x2, #1
    b       .Lpc_len
.Lpc_go:
    mov     x0, #1                  // stdout
    movz    x16, #0x0004
    movk    x16, #0x0200, lsl #16 
    svc     #0
    ldp     x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------
// _itoa(x0 = signed 64-bit value, x1 = dest buffer) -> writes decimal
// ASCII digits + NUL into dest. Handles negative numbers.
// -----------------------------------------------------------------
_itoa:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    mov     x19, x1                 // x19 = dest cursor (write forward later)
    mov     x2, x0
    mov     x3, #0                  // negative flag
    cmp     x2, #0
    b.ge    .Lit_nonneg
    mov     x3, #1
    neg     x2, x2
.Lit_nonneg:
    // build digits in reverse into tok_buf, then copy out reversed
    adrp    x4, tok_buf@PAGE
    add     x4, x4, tok_buf@PAGEOFF
    mov     x20, x4                 // x20 = scratch cursor
    mov     x5, #10
.Lit_digit_loop:
    udiv    x6, x2, x5
    msub    x7, x6, x5, x2          // x7 = x2 % 10
    add     x7, x7, #'0'
    strb    w7, [x20], #1
    mov     x2, x6
    cbnz    x2, .Lit_digit_loop

    cbz     x3, .Lit_copy_out
    mov     w7, #'-'
    strb    w7, [x20], #1
.Lit_copy_out:
    // x20 currently points one past the last digit written (reverse order)
.Lit_out_loop:
    sub     x20, x20, #1
    ldrb    w7, [x20]
    strb    w7, [x19], #1
    adrp    x4, tok_buf@PAGE
    add     x4, x4, tok_buf@PAGEOFF
    cmp     x20, x4
    b.gt    .Lit_out_loop
    strb    wzr, [x19]

    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldp     x29, x30, [sp], #32
    ret

// -----------------------------------------------------------------
// _find_tag(x0 = name ptr) -> x0 = record ptr or 0 if not found
// -----------------------------------------------------------------
_find_tag:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x9, x0                  // name to find
    adrp    x10, tag_list_head@PAGE
    add     x10, x10, tag_list_head@PAGEOFF
    ldr     x10, [x10]              // x10 = current node
.Lft_loop:
    cbz     x10, .Lft_notfound
    ldr     x1, [x10, #8]           // node->name
    mov     x0, x9
    bl      _streq
    cbnz    x0, .Lft_found
    ldr     x10, [x10]              // node->next
    b       .Lft_loop
.Lft_found:
    mov     x0, x10
    ldp     x29, x30, [sp], #16
    ret
.Lft_notfound:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------
// _streq(x0, x1) -> x0 = 1 if equal NUL-terminated strings, else 0
// -----------------------------------------------------------------
_streq:
.Lse_loop:
    ldrb    w2, [x0]
    ldrb    w3, [x1]
    cmp     w2, w3
    b.ne    .Lse_no
    cbz     w2, .Lse_yes
    add     x0, x0, #1
    add     x1, x1, #1
    b       .Lse_loop
.Lse_yes:
    mov     x0, #1
    ret
.Lse_no:
    mov     x0, #0
    ret

// -----------------------------------------------------------------
// _strdup_static(x0 = src) -> x0 = pointer into tag_name_buf with a
// copy of src (NOTE: single scratch slot — caller must persist the
// bytes elsewhere, e.g. by allocating a fresh node, before the next
// call overwrites it; see _create_tag which copies into node memory
// via a bump allocator instead of relying on this scratch copy)
// -----------------------------------------------------------------
_strdup_static:
    adrp    x1, tag_name_buf@PAGE
    add     x1, x1, tag_name_buf@PAGEOFF
    mov     x2, x1
.Lsd_loop:
    ldrb    w3, [x0], #1
    strb    w3, [x2], #1
    cbnz    w3, .Lsd_loop
    mov     x0, x1
    ret

// =================================================================
// MODULE 2b: bump allocator for Tag records + name/string storage
// (No free() needed for an interpreter that lives for one run.)
// =================================================================
.bss
.align 4
heap_pool:      .skip 262144     // 256 KB bump-allocated heap
.data
.align 4
heap_cursor_init: .quad 0
.bss
heap_cursor:    .skip 8
.text

// -----------------------------------------------------------------
// _bump_alloc(x0 = size) -> x0 = pointer to size bytes, 8-byte aligned
// -----------------------------------------------------------------
_bump_alloc:
    adrp    x1, heap_cursor@PAGE
    add     x1, x1, heap_cursor@PAGEOFF
    ldr     x2, [x1]                // current offset
    cbnz    x2, .Lba_have_base
    // first call: base = heap_pool
.Lba_have_base:
    adrp    x3, heap_pool@PAGE
    add     x3, x3, heap_pool@PAGEOFF
    add     x4, x3, x2              // pointer to return
    add     x5, x0, #7
    and     x5, x5, #~7             // round size up to 8
    add     x2, x2, x5
    str     x2, [x1]
    mov     x0, x4
    ret

// -----------------------------------------------------------------
// _create_tag(x0 = name ptr, x1 = type, x2 = int value, x3 = str value ptr or 0)
//   -> x0 = new record ptr. Copies the name into permanent heap memory.
// -----------------------------------------------------------------
_create_tag:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    mov     x19, x0                 // name (scratch, must copy)
    mov     x20, x1                 // type
    mov     x21, x2                 // int value
    mov     x22, x3                 // str value

    // duplicate the name into the bump heap so it outlives tok_buf/line_buf
    mov     x0, #128
    bl      _bump_alloc
    mov     x9, x0                  // x9 = permanent name buffer
    mov     x10, x9
.Lct_copy_name:
    ldrb    w11, [x19], #1
    strb    w11, [x10], #1
    cbnz    w11, .Lct_copy_name

    // allocate the record itself
    mov     x0, #TAG_SIZE
    bl      _bump_alloc
    mov     x12, x0                 // x12 = new record

    adrp    x13, tag_list_head@PAGE
    add     x13, x13, tag_list_head@PAGEOFF
    ldr     x14, [x13]              // old head
    str     x14, [x12]              // node->next = old head
    str     x9,  [x12, #8]          // node->name
    str     x20, [x12, #16]         // node->type
    str     x21, [x12, #24]         // node->int value
    str     x22, [x12, #32]         // node->str value
    mov     x15, #1
    str     x15, [x12, #40]         // node->assignment level = 1 (first write)

    str     x12, [x13]              // tag_list_head = node

    mov     x0, x12
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldr     x22, [sp, #40]
    ldp     x29, x30, [sp], #48
    ret

// =================================================================
// MODULE 3: line handlers — Tag., Terminal, Op of, Dif in
// =================================================================

// -----------------------------------------------------------------
// _parse_int(x0 = decimal ASCII string ptr) -> x0 = int64 value
// Stops at first non-digit. Supports a leading '-'.
// -----------------------------------------------------------------
_parse_int:
    mov     x1, #0                  // accumulator
    mov     x2, #0                  // neg flag
    ldrb    w3, [x0]
    cmp     w3, #'-'
    b.ne    .Lpi_loop
    mov     x2, #1
    add     x0, x0, #1
.Lpi_loop:
    ldrb    w3, [x0]
    cmp     w3, #'0'
    b.lt    .Lpi_done
    cmp     w3, #'9'
    b.gt    .Lpi_done
    sub     w3, w3, #'0'
    mov     x4, #10
    mul     x1, x1, x4
    add     x1, x1, x3
    add     x0, x0, #1
    b       .Lpi_loop
.Lpi_done:
    cbz     x2, .Lpi_ret
    neg     x1, x1
.Lpi_ret:
    mov     x0, x1
    ret

// -----------------------------------------------------------------
// _handle_tag_line(x0 = line starting at "Tag.")
//   Parses:  Tag.name = type.value
//            Tag.name += type.value
//            Tag.name ++= type.value  (etc. — '+' count = law, not enforced
//            strictly here; see NOTES.md for the strict-check extension)
// -----------------------------------------------------------------
_handle_tag_line:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    str     x23, [sp, #48]
    str     x24, [sp, #56]

    add     x9, x0, #4              // skip "Tag."

    // copy tag name (up to space or '+' or '=') into tag_name_buf
    adrp    x10, tag_name_buf@PAGE
    add     x10, x10, tag_name_buf@PAGEOFF
    mov     x11, x10
.Lht_name:
    ldrb    w12, [x9]
    cmp     w12, #' '
    b.eq    .Lht_name_done
    cmp     w12, #'+'
    b.eq    .Lht_name_done
    cmp     w12, #'='
    b.eq    .Lht_name_done
    strb    w12, [x11], #1
    add     x9, x9, #1
    b       .Lht_name
.Lht_name_done:
    strb    wzr, [x11]
    mov     x19, x10                // x19 = tag name string

    // skip spaces / count '+' characters (reassignment level) / skip '='
.Lht_skip_to_eq:
    ldrb    w12, [x9]
    cbz     w12, .Lht_bail           // malformed line, bail out quietly
    cmp     w12, #'='
    b.eq    .Lht_after_eq
    add     x9, x9, #1
    b       .Lht_skip_to_eq
.Lht_after_eq:
    add     x9, x9, #1               // consume '='
.Lht_skip_sp2:
    ldrb    w12, [x9]
    cmp     w12, #' '
    b.ne    .Lht_type_start
    add     x9, x9, #1
    b       .Lht_skip_sp2
.Lht_type_start:
    // determine type by prefix: num. / state. / blea.
    adrp    x1, str_num@PAGE
    add     x1, x1, str_num@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Lht_try_state
    add     x9, x9, #4
    mov     x20, #TAG_NUM
    b       .Lht_value

.Lht_try_state:
    adrp    x1, str_state@PAGE
    add     x1, x1, str_state@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Lht_try_blea
    add     x9, x9, #6
    mov     x20, #TAG_STATE
    b       .Lht_value

.Lht_try_blea:
    adrp    x1, str_blea@PAGE
    add     x1, x1, str_blea@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    cbz     x0, .Lht_bail
    add     x9, x9, #5
    mov     x20, #TAG_BLEA
    // fall through: x9 now points at the blea text

.Lht_value:
    cmp     x20, #TAG_NUM
    b.eq    .Lht_val_num
    cmp     x20, #TAG_STATE
    b.eq    .Lht_val_state
    // TAG_BLEA: duplicate the rest of the line into the heap as the string value
    mov     x0, x9
    bl      _heap_strdup
    mov     x21, x0                 // str value ptr
    mov     x2, #0                  // int value unused
    mov     x3, x21
    b       .Lht_store

.Lht_val_num:
    mov     x0, x9
    bl      _parse_int
    mov     x2, x0
    mov     x3, #0
    b       .Lht_store

.Lht_val_state:
    adrp    x1, str_true@PAGE
    add     x1, x1, str_true@PAGEOFF
    mov     x0, x9
    bl      _starts_with
    mov     x2, x0                  // 1 if true, 0 if false/other
    mov     x3, #0
    b       .Lht_store


.Lht_store:
    // stash the parsed value/type in callee-saved regs BEFORE any call
    mov     x22, x20                  // type
    mov     x23, x2                   // int value
    mov     x24, x3                   // str value ptr

    mov     x0, x19
    bl      _find_tag
    cbz     x0, .Lht_new
    // existing tag: update value + type, increment assignment level
    str     x22, [x0, #16]
    str     x23, [x0, #24]
    str     x24, [x0, #32]
    ldr     x1, [x0, #40]
    add     x1, x1, #1
    str     x1, [x0, #40]
    b       .Lht_bail
.Lht_new:
    mov     x0, x19
    mov     x1, x22
    mov     x2, x23
    mov     x3, x24
    bl      _create_tag

.Lht_bail:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldr     x22, [sp, #40]
    ldr     x23, [sp, #48]
    ldr     x24, [sp, #56]
    ldp     x29, x30, [sp], #64
    ret

// -----------------------------------------------------------------
// _heap_strdup(x0 = src ptr, NUL or up to line end) -> x0 = heap copy
// -----------------------------------------------------------------
_heap_strdup:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x9, x0
    mov     x0, #256
    bl      _bump_alloc
    mov     x10, x0
    mov     x11, x10
.Lhs_loop:
    ldrb    w12, [x9], #1
    strb    w12, [x11], #1
    cbnz    w12, .Lhs_loop
    mov     x0, x10
    ldp     x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------
// _handle_terminal_line(x0 = line starting at "Terminal")
//   Terminal 'name'  -> prints the tag's value + newline
// -----------------------------------------------------------------
_handle_terminal_line:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    add     x9, x0, #8               // skip "Terminal"
.Lht2_skip:
    ldrb    w10, [x9]
    cmp     w10, #' '
    b.eq    .Lht2_adv
    cmp     w10, #0x27               // '\''
    b.eq    .Lht2_quote
    b       .Lht2_bail
.Lht2_adv:
    add     x9, x9, #1
    b       .Lht2_skip
.Lht2_quote:
    add     x9, x9, #1               // consume opening quote
    adrp    x10, tag_name_buf@PAGE
    add     x10, x10, tag_name_buf@PAGEOFF
    mov     x11, x10
.Lht2_name:
    ldrb    w12, [x9]
    cbz     w12, .Lht2_name_done
    cmp     w12, #0x27
    b.eq    .Lht2_name_done
    strb    w12, [x11], #1
    add     x9, x9, #1
    b       .Lht2_name
.Lht2_name_done:
    strb    wzr, [x11]

    mov     x0, x10
    bl      _find_tag
    cbz     x0, .Lht2_bail           // unknown tag: nothing to print

    ldr     x1, [x0, #16]            // type
    cmp     x1, #TAG_NUM
    b.eq    .Lht2_print_num
    cmp     x1, #TAG_STATE
    b.eq    .Lht2_print_state
    // TAG_BLEA (or logic — not printable, skip)
    cmp     x1, #TAG_BLEA
    b.ne    .Lht2_bail
    ldr     x0, [x0, #32]
    bl      _print_cstr
    b       .Lht2_nl

.Lht2_print_num:
    ldr     x0, [x0, #24]
    adrp    x1, num_str_buf@PAGE
    add     x1, x1, num_str_buf@PAGEOFF
    bl      _itoa
    mov     x0, x1
    bl      _print_cstr
    b       .Lht2_nl

.Lht2_print_state:
    ldr     x2, [x0, #24]
    cbz     x2, .Lht2_false
    adrp    x0, str_true@PAGE
    add     x0, x0, str_true@PAGEOFF
    b       .Lht2_print_it
.Lht2_false:
    adrp    x0, str_false@PAGE
    add     x0, x0, str_false@PAGEOFF
.Lht2_print_it:
    bl      _print_cstr

.Lht2_nl:
    adrp    x0, newline@PAGE
    add     x0, x0, newline@PAGEOFF
    bl      _print_cstr
.Lht2_bail:
    ldp     x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------
// _handle_op_line(x0 = line starting at "Op of")
//   Op of A add B ==   (A, B are tag names or numeric literals)
//   Supported: add, subtract, times, divide  (num only in this pass;
//   cos/tan and mixed-type concatenation are extension points — see
//   NOTES.md — the branch structure below is where they plug in)
//   Result is stored into a synthetic tag named "_" so a following
//   "Terminal '_'" can print it, matching the spec's demo pattern.
// -----------------------------------------------------------------
_handle_op_line:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]

    add     x20, x0, #5              // skip "Op of"  (x20 = callee-saved cursor)
.Lop_skip1:
    ldrb    w10, [x20]
    cmp     w10, #' '
    b.ne    .Lop_read_a
    add     x20, x20, #1
    b       .Lop_skip1

.Lop_read_a:
    // read operand A token
    adrp    x10, tok_buf@PAGE
    add     x10, x10, tok_buf@PAGEOFF
    mov     x11, x10
.Lop_a_loop:
    ldrb    w12, [x20]
    cbz     w12, .Lop_bail
    cmp     w12, #' '
    b.eq    .Lop_a_done
    strb    w12, [x11], #1
    add     x20, x20, #1
    b       .Lop_a_loop
.Lop_a_done:
    strb    wzr, [x11]
    mov     x0, x10
    bl      _resolve_operand         // -> x0 = int value of A (x20 survives: callee-saved)
    mov     x19, x0                  // x19 = A

.Lop_skip2:
    ldrb    w12, [x20]
    cmp     w12, #' '
    b.ne    .Lop_read_op
    add     x20, x20, #1
    b       .Lop_skip2

.Lop_read_op:
    // read operator keyword (add/subtract/times/divide/cos/tan)
    adrp    x10, tag_name_buf@PAGE
    add     x10, x10, tag_name_buf@PAGEOFF
    mov     x11, x10
.Lop_op_loop:
    ldrb    w12, [x20]
    cbz     w12, .Lop_bail
    cmp     w12, #' '
    b.eq    .Lop_op_done
    strb    w12, [x11], #1
    add     x20, x20, #1
    b       .Lop_op_loop
.Lop_op_done:
    strb    wzr, [x11]

.Lop_skip3:
    ldrb    w12, [x20]
    cmp     w12, #' '
    b.ne    .Lop_read_b
    add     x20, x20, #1
    b       .Lop_skip3

.Lop_read_b:
    adrp    x13, tok_buf@PAGE
    add     x13, x13, tok_buf@PAGEOFF
    mov     x14, x13
.Lop_b_loop:
    ldrb    w12, [x20]
    cbz     w12, .Lop_b_done2
    cmp     w12, #' '
    b.eq    .Lop_b_done
    cmp     w12, #'='
    b.eq    .Lop_b_done
    strb    w12, [x14], #1
    add     x20, x20, #1
    b       .Lop_b_loop
.Lop_b_done:
.Lop_b_done2:
    strb    wzr, [x14]

    adrp    x0, tag_name_buf@PAGE
    add     x0, x0, tag_name_buf@PAGEOFF
    adrp    x1, tok_buf@PAGE
    add     x1, x1, tok_buf@PAGEOFF
    mov     x2, x19                    // A value
    bl      _apply_operator            // x0 = op string, x1 = B token, x2 = A -> returns result in x0
    mov     x19, x0                   // stash result in x19 (callee-saved: survives bl _find_tag)

    // store result into synthetic tag "_"
    adrp    x0, .Lop_result_name@PAGE
    add     x0, x0, .Lop_result_name@PAGEOFF
    bl      _find_tag
    cbz     x0, .Lop_new_result
    mov     x9, #TAG_NUM
    str     x9, [x0, #16]
    str     x19, [x0, #24]
    ldr     x1, [x0, #40]
    add     x1, x1, #1
    str     x1, [x0, #40]
    b       .Lop_bail
.Lop_new_result:
    adrp    x0, .Lop_result_name@PAGE
    add     x0, x0, .Lop_result_name@PAGEOFF
    mov     x1, #TAG_NUM
    mov     x2, x19
    mov     x3, #0
    bl      _create_tag

.Lop_bail:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldp     x29, x30, [sp], #32
    ret

.data
.align 4
.Lop_add_s:      .asciz "add"
.Lop_sub_s:      .asciz "subtract"
.Lop_mul_s:       .asciz "times"
.Lop_div_s:       .asciz "divide"
.Lop_result_name: .asciz "_"
.text

// -----------------------------------------------------------------
// _apply_operator(x0 = operator name ptr, x1 = B token ptr, x2 = A value)
//   -> x0 = result. Resolves B via _resolve_operand, then applies
//   the operator named in tag_name_buf (add/subtract/times/divide).
//   cos/tan are stubbed to return A unchanged (extension point).
// -----------------------------------------------------------------

_apply_operator:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    mov     x19, x0                  // op name
    mov     x20, x2                  // A value
    mov     x0, x1
    bl      _resolve_operand
    mov     x21, x0                  // B value (callee-saved: survives bl _streq below)

    mov     x0, x19
    adrp    x1, .Lop_add_s@PAGE
    add     x1, x1, .Lop_add_s@PAGEOFF
    bl      _streq
    cbz     x0, .Lao_try_sub
    add     x0, x20, x21
    b       .Lao_done

.Lao_try_sub:
    mov     x0, x19
    adrp    x1, .Lop_sub_s@PAGE
    add     x1, x1, .Lop_sub_s@PAGEOFF
    bl      _streq
    cbz     x0, .Lao_try_mul
    sub     x0, x20, x21
    b       .Lao_done

.Lao_try_mul:
    mov     x0, x19
    adrp    x1, .Lop_mul_s@PAGE
    add     x1, x1, .Lop_mul_s@PAGEOFF
    bl      _streq
    cbz     x0, .Lao_try_div
    mul     x0, x20, x21
    b       .Lao_done

.Lao_try_div:
    mov     x0, x19
    adrp    x1, .Lop_div_s@PAGE
    add     x1, x1, .Lop_div_s@PAGEOFF
    bl      _streq
    cbz     x0, .Lao_default
    cbz     x21, .Lao_divzero
    sdiv    x0, x20, x21
    b       .Lao_done
.Lao_divzero:
    mov     x0, #0
    b       .Lao_done

.Lao_default:
    // cos/tan/unrecognized: extension point, currently pass A through
    mov     x0, x20

.Lao_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// -----------------------------------------------------------------
// _resolve_operand(x0 = token ptr) -> x0 = int64 value
//   If the token names an existing num/state tag, returns its value.
//   Otherwise parses it as a numeric literal.
// -----------------------------------------------------------------
_resolve_operand:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x9, x0
    bl      _find_tag
    cbz     x0, .Lro_literal
    ldr     x0, [x0, #24]             // int value field works for num & state
    b       .Lro_done
.Lro_literal:
    mov     x0, x9
    bl      _parse_int
.Lro_done:
    ldp     x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------
// _handle_dif_line(x0 = line starting at "Dif in")
//   Dif in a, b, c   -> prints "name = type += level\n" per tag
//   (simplified single-line-per-tag form of the spec's example)
// -----------------------------------------------------------------
_handle_dif_line:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x20, [sp, #16]
    add     x19, x0, #6                // skip "Dif in"  (x19 = callee-saved cursor)

.Ldif_next:
.Ldif_skip_sp:
    ldrb    w10, [x19]
    cbz     w10, .Ldif_bail
    cmp     w10, #' '
    b.eq    .Ldif_adv
    cmp     w10, #','
    b.eq    .Ldif_adv
    b       .Ldif_read
.Ldif_adv:
    add     x19, x19, #1
    b       .Ldif_skip_sp
.Ldif_read:
    adrp    x10, tag_name_buf@PAGE
    add     x10, x10, tag_name_buf@PAGEOFF
    mov     x11, x10
.Ldif_read_loop:
    ldrb    w12, [x19]
    cbz     w12, .Ldif_read_done
    cmp     w12, #','
    b.eq    .Ldif_read_done
    strb    w12, [x11], #1
    add     x19, x19, #1
    b       .Ldif_read_loop
.Ldif_read_done:
    strb    wzr, [x11]

    mov     x20, x10                  // stash name-buffer ptr in callee-saved reg too
    mov     x0, x10
    bl      _find_tag
    cbz     x0, .Ldif_next            // unknown tag: skip

    // print "name = "
    mov     x21, x0                   // record ptr (survives calls below via reload pattern)
    str     x21, [sp, #-16]!          // stash on stack (simple, avoids extra callee-saved regs)
    mov     x0, x20
    bl      _print_cstr
    adrp    x0, .Ldif_eq@PAGE
    add     x0, x0, .Ldif_eq@PAGEOFF
    bl      _print_cstr

    ldr     x21, [sp], #16
    ldr     x1, [x21, #16]            // type
    cmp     x1, #TAG_NUM
    b.eq    .Ldif_pnum
    cmp     x1, #TAG_STATE
    b.eq    .Ldif_pstate
    adrp    x0, .Ldif_blea@PAGE
    add     x0, x0, .Ldif_blea@PAGEOFF
    b       .Ldif_ptype
.Ldif_pnum:
    adrp    x0, .Ldif_num@PAGE
    add     x0, x0, .Ldif_num@PAGEOFF
    b       .Ldif_ptype
.Ldif_pstate:
    adrp    x0, .Ldif_state@PAGE
    add     x0, x0, .Ldif_state@PAGEOFF
.Ldif_ptype:
    bl      _print_cstr

    ldr     x0, [x21, #40]             // assignment level
    adrp    x1, num_str_buf@PAGE
    add     x1, x1, num_str_buf@PAGEOFF
    bl      _itoa
    mov     x0, x1
    bl      _print_cstr
    adrp    x0, newline@PAGE
    add     x0, x0, newline@PAGEOFF
    bl      _print_cstr

    b       .Ldif_next

.Ldif_bail:
    ldr     x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.data
.align 4
.Ldif_eq:    .asciz " = "
.Ldif_num:   .asciz "num, level "
.Ldif_state: .asciz "state, level "
.Ldif_blea:  .asciz "blea, level "
.text
