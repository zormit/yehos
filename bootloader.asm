; compile with nasm, use as disk image to qemu-system-i386
;; note this uses x86 assembly intel syntax (so `mov dest, src`)

[BITS 16]     ;; assembler directive telling nasm to generate code for processor running
              ;; in 16-bit mode.
[ORG 0x7c00]  ;; start the "location counter" (i.e. set origin) to 0x7c00,
              ;; which is the typical location that the BIOS loads the boot sector
              ;; (i.e. this code, which is generally found at the first sector on a HDD.

boot_drive equ $ ;; similar to C's #DEFINE: sets label 'boot_drive' to the location of this line
                 ;; in the resulting code file after assembling (assembly-time calculation)

entry:                 ;; note the <label>: syntax makes the <label> refer to the memory locationcontaining the instruction on the following line.
    cli                ;; clear interrupt flag (disable interrupts)
    jmp 0x0000:start   ;; jump to location defined by this segment address. 
                       ;; this is translated to a 20-bit linear address (i.e. physical)
                       ;; by shifting segment 4 bits << and adding to offset (here, 'start')
                       ;; this sets CS:IP to these values. This jumps over the next couple data 
                       ;; sections to the actual code.

    times (8 - $ + entry) db 0   ; pad until boot-info-table (where did this formulat come from?
                                 ;; this places 0's in the bytes following this instruction a certain number of times.

; don't bother with making el torito load the kernel image
iso_boot_info:
bi_pvd  dd 16           ; LBA of primary volume descriptor
bi_file dd 0            ; LBA of boot file
bi_len  dd 0            ; len of boot file
bi_csum dd 0
bi_reserved times 10 dd 0

banner db 10, "SP/OS (2013) Saul Pwanson", 13, 10, 0  ;; 'banner' now refers to memory location 
                                                      ;; of the first byte, 10, in this following sequence. (note that it ends with an ascii \r\n\0
errstr db "error loading kernel", 0

; Disk Address Packet
dap db 16, 0            ; [2] sizeof(dap)
dap_num_sects    dw 1                ; [2] transfer 1 sectors (before PVB)
dap_addr   dw 0x4000, 0x0      ; [4] to 0:4000
dap_lba    dd 0, 0             ; [8] from LBA 0

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax          ;; clear out all segment registers
    mov sp, 0x7c00      ; setup stack just before the code (recall stack grows towards 0x0)

    mov [boot_drive], dl ;; save off boot_drive (? moves content of lower 8-bits of dx register
                         ;; into the location referenced by boot_drive) 
                         ;; The saves off the drive that the bootloader was loaded in from,
                         ;; (set up by the BIOS), useful if you want to read more in from disk.
                         ;; see https://en.wikibooks.org/wiki/X86_Assembly/Bootloaders

    ; display banner
    mov si, banner       ;; moves 
    call writestr

    ; read first sector from disk
    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jnc readok

readerr:
    mov si, errstr
    call writestr
    hlt

readok:
    ; at 0x4000 is kernel sector lba (u16)
    ; at 0x4002 is number of kernel sectors (u16)
    ; read kernel from disk
    mov ax, [0x4002]
    mov [dap_num_sects], ax
    mov ax, [0x4000]
    mov [dap_lba], ax
    mov ax, 0x8000
    mov [dap_addr], ax

    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc readerr

leap:
    call enable_A20

    lgdt [GDT]                      ; ge
    mov eax, cr0                    ; ro
    or al, 1                        ; ni
    mov cr0, eax                    ; mo
    jmp 0x08:protmain               ; !!

enable_A20: ; from wiki.osdev.org
    call a20wait
    mov al,0xAD
    out 0x64,al

    call a20wait
    mov al,0xD0
    out 0x64,al

    call a20wait2
    in al,0x60
    push eax

    call a20wait
    mov al,0xD1
    out 0x64,al

    call a20wait
    pop eax
    or al,2
    out 0x60,al

    call a20wait
    mov al,0xAE
    out 0x64,al

;  fall-through
;    call a20wait
;    ret

a20wait:
    in al,0x64
    test al,2
    jnz a20wait
    ret

a20wait2:
    in al,0x64
    test al,1
    jz a20wait2
    ret

; character to print in al
putc:
    push ax
    push bx
    mov ah, 0x0e
    mov bx, 0x000f
    int 0x10
    pop bx
    pop ax
    ret

writestr:
    lodsb
    test al, al
    jz end
    call putc
    jmp writestr
end:
    ret

; --- protected mode ---
[BITS 32]

GDT    dw 0x28                      ; limit of 5 entries
       dd GDT                       ; linear address of GDT
       dw 0
        ; 0xBBBBLLLL, 0xBBFLAABB    ; F = GS00b, AA = 1001XDW0
gdtCS  dd 0x0000ffff, 0x00CF9A00    ; 0x08
gdtDS  dd 0x0000ffff, 0x00CF9200    ; 0x10

protmain:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax

    mov esp, 0x6000      ; data stack grows down

    mov eax, 0x8000
    call eax

_halt:
    hlt
    jmp _halt

    times (512 - $ + entry - 2) db 0 ; pad boot sector with zeroes

       db 0x55, 0xAA ; 2 byte boot signature
