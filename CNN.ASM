.686
.xmm
.model flat,stdcall

includelib kernel32.lib

DO_NOT_SHARE = 0
NULL         = 0
TRUE         = 1
FALSE        = 0

TAB EQU 09H
ENDL EQU 0dH,0aH

HANDLE TEXTEQU <DWORD> ; used in Win32 API documentation

; Win32 Console handle
STD_OUTPUT_HANDLE EQU -11 ; predefined Win API constant
STD_INPUT_HANDLE EQU -10 ; predefined Win API constant

; Constants found in WINNT.H
FILE_SHARE_READ       = 1
FILE_ATTRIBUTE_NORMAL = 80H

GENERIC_READ  = 80000000H
GENERIC_WRITE = 40000000H

; Memory allocation constants
HEAP_ZERO_MEMORY = 00000008H

;------------------ From winbase.h ----------------------------
CREATE_ALWAYS = 2
OPEN_EXISTING = 3

INVALID_HANDLE_VALUE = -1

;==============================================================
CloseHandle PROTO,; close file handle
    hObject:DWORD

CreateFileA PROTO,              ; create new file
    lpFilename:PTR BYTE,        ; ptr to filename
    dwDesiredAccess:DWORD,      ; access mode
    dwShareMode:DWORD,          ; share mode
    lpSecurityAttributes:DWORD, ; pointer to security attributes
    dwCreationDisposition:DWORD,; file creation options
    dwFlagsAndAttributes:DWORD, ; file attributes
    hTemplateFile:DWORD          ; handle to template file

GetStdHandle PROTO,  ; get standard handle
    nStdHandle:HANDLE ; type of console handle

GetProcessHeap PROTO ; Get the current process heap handle

HeapAlloc PROTO,
    hHeap:HANDLE, ; handle to private heap block
    dwFlags:DWORD,; heap allocation control flags
    dwBytes:DWORD  ; number of bytes to allocate

HeapFree PROTO,
    hHeap:HANDLE, ; handle to heap with memory block
    dwFlags:DWORD,; heap free options
    lpMem:DWORD    ; pointer to block to be freed

ReadFile PROTO,                   ; read buffer from input file
    hFile:HANDLE,                 ; input handle
    lpBuffer:PTR BYTE,            ; ptr to buffer
    nNumberOfBytesToRead:DWORD,   ; num bytes to read
    lpNumberOfBytesRead:PTR DWORD,; bytes actually read
    lpOverlapped:PTR DWORD         ; ptr to asynchronous info

ReadConsoleA PROTO,
    hConsoleInput: HANDLE,                       ;输入句柄
    lpBuffer:PTR BYTE,                                   ;缓冲区指针
    nNumberOfCharsToRead:DWORD,         ;读取的字符数
    lpNumberOfCharsRead:PTR DWORD,     ;指向读取字节数的指针
    lpReserved:DWORD                                 ;未使用

WriteConsoleA PROTO,                 ; write a buffer to the console
    hConsoleOutput:HANDLE,           ; output handle
    lpBuffer:PTR BYTE,               ; pointer to buffer
    nNumberOfCharsToWrite:DWORD,     ; size of buffer
    lpNumberOfCharsWritten:PTR DWORD,; ptr to number of bytes written
    lpReserved:DWORD                  ; (not used)

WriteFile PROTO,                     ; write buffer to output file
    hFile:HANDLE,                    ; output handle
    lpBuffer:PTR BYTE,               ; pointer to buffer
    nNumberOfBytesToWrite:DWORD,     ; size of buffer
    lpNumberOfBytesWritten:PTR DWORD,; num bytes written
    lpOverlapped:PTR DWORD            ; ptr to asynchronous info

;===============================================================;

;------------------------------------------------------------;
;							初始化							；
;------------------------------------------------------------;
.data?
    align 4
    __stdout_handle HANDLE ?
    __stdin_handle HANDLE ?
	__heap_handle HANDLE ?
	COMM	_image_number:DWORD
	COMM	_magic_number:DWORD
	COMM	_n_rows:DWORD
	COMM	_CNN:BYTE:019760H
	COMM	_n_cols:DWORD
	COMM	_temp_Pool:QWORD:0310H
	ORG $+7
.code

new macro dwBytes;字节数;eax 空间的开始地址
    invoke HeapAlloc,
        __heap_handle, ;hHeap
        HEAP_ZERO_MEMORY,                    ;dwFlags
        dwBytes               ;dwBytes
endm
delete macro lpMem ;空间的开始地址;eax 空间释放成功与否
    invoke HeapFree,
        __heap_handle, ;hHeap
        0,                    ;dwFlags
        lpMem                 ;lpMem
endm
init_sys_env macro
    invoke GetStdHandle,
        STD_OUTPUT_HANDLE ;nStdHandle
    mov __stdout_handle,eax

    invoke GetStdHandle,
        STD_INPUT_HANDLE ;nStdHandle
    mov __stdin_handle,eax
	
    invoke GetProcessHeap
    mov __heap_handle,eax

	new BUFFER_SIZE
    mov buffer,eax
    new TRAIN_SIZE*8
    mov _labels,eax
    new TRAIN_SIZE*IMAGE_SIZE*8
    mov _images,eax
ENDM
;------------------------------------------------------------;
;							数学								；
;------------------------------------------------------------;
.const
	align 16
	xmm_7fX      DQ 7fffffffffffffffH,7fffffffffffffffH
	xmm_255_0_X2 DQ 406fe00000000000H,406fe00000000000H ;255.0,255.0
	real__1E9	 DQ 0c1cdcd6500000000r	; -1e9
	real__1E8    DQ 0c197d78400000000r ;-1e8
	real__1E3    DQ 0c08f400000000000r ;-1000
	real__100	 DQ 0c059000000000000r	; -100
	real__1      DQ 0bff0000000000000r ;-1
	real_20000   DQ 040d3880000000000r ;20000
	real_5000    DQ 040b3880000000000r ;5000
	real_3000	 DQ 040a7700000000000r	; 3000
	real_1024	 DQ 04090000000000000r	; 1024
	real_255		 DQ 0406fe00000000000r	; 255
	real_100     DQ 04059000000000000r ;100
	real_95		 DQ 04057c00000000000r	; 95
	real_1       DQ 03ff0000000000000r ;1
	real_0_01    DQ 03f847ae147ae147br ;0.01
	real_2e_10   DQ 03f50000000000000r ;0.000976562, 1/1024
	real_0       DQ 00000000000000000r ;0
	;_eta			 DQ	03f847ae147ae147br		; 0.005
	_eta			 DQ	03f747ae147ae147br		; 0.005

.data
	_randSeed	 DD	0457H
.code
;伪随机数
_TEXT	SEGMENT
_res_ = -4						; size = 4
_m_ = 8							; size = 4
_Rand	PROC						;  
;int Rand(int m)
	push	ebp
	mov	ebp, esp
	push	ecx
;uint res = randSeed;
	mov	eax, DWORD PTR _randSeed
	mov	DWORD PTR _res_[ebp], eax
;res = res * 1127 + 12122;
	imul	ecx, DWORD PTR _res_[ebp], 1127
	add	ecx, 12122				; 00002f5aH
	mov	DWORD PTR _res_[ebp], ecx
;randSeed = res;
	mov	edx, DWORD PTR _res_[ebp]
	mov	DWORD PTR _randSeed, edx
;res %= 6531;
	mov	eax, DWORD PTR _res_[ebp]
	xor	edx, edx
	mov	ecx, 6531				; 00001983H
	div	ecx
	mov	DWORD PTR _res_[ebp], edx
; 78   : 	res = res * 2333 + 812931;
	imul	edx, DWORD PTR _res_[ebp], 2333
	add	edx, 812931				; 000c6783H
	mov	DWORD PTR _res_[ebp], edx
;return res % m;
	mov	eax, DWORD PTR _res_[ebp]
	xor	edx, edx
	div	DWORD PTR _m_[ebp]
	mov	eax, edx
	mov	esp, ebp
	pop	ebp
	ret	0
_Rand	ENDP
_TEXT	ENDS

;max函数
_TEXT	SEGMENT
_m_ = 8							; size = 8
_n_ = 16						; size = 8
_dMax	PROC						;  
;double dMax(double m, double n)
	push	ebp
	mov	ebp, esp
;if (m > n) return m;
	movsd	xmm0, QWORD PTR _m_[ebp]
	comisd	xmm0, QWORD PTR _n_[ebp]
	jbe	SHORT _Label2@dMax
	fld	QWORD PTR _m_[ebp]
	jmp	SHORT _Label1@dMax
_Label2@dMax:
;return n;
	fld	QWORD PTR _n_[ebp]
_Label1@dMax:
	pop	ebp
	ret	0
_dMax	ENDP
_TEXT	ENDS
;Relu函数
_TEXT	SEGMENT
_x_ = 8							; size = 8
_Relu	PROC						;  
;double Relu(double x)
	push	ebp
	mov	ebp, esp
;if (x > 0)return x;
	movsd	xmm0, QWORD PTR _x_[ebp]
	comisd	xmm0, QWORD PTR real_0
	jbe	SHORT _Label2@Relu
	fld	QWORD PTR _x_[ebp]
	jmp	SHORT _Label1@Relu
_Label2@Relu:
;return 0;
	fldz
_Label1@Relu:
	pop	ebp
	ret	0
_Relu	ENDP
_TEXT	ENDS
;自然指数
_TEXT	SEGMENT
_i_1 = -4						; size = 4
_x_ = 8							; size = 8
_Exp	PROC						;  
; 98   : __declspec(noinline) double Exp(double x) {
	push	ebp
	mov	ebp, esp
	push	ecx
; 99   : 	if (x < -1000) return 0;
	movsd	xmm0, QWORD PTR real__1E3
	comisd	xmm0, QWORD PTR _x_[ebp]
	jbe	SHORT _Label5@Exp
	fldz
	jmp	SHORT _Label1@Exp
_Label5@Exp:
;x = 1.0 + x / 1024;
	movsd	xmm0, QWORD PTR _x_[ebp]
	divsd	xmm0, QWORD PTR real_1024
	addsd	xmm0, QWORD PTR real_1
	movsd	QWORD PTR _x_[ebp], xmm0
;REP(i, 10) x *= x;
	mov	DWORD PTR _i_1[ebp], 0
	jmp	SHORT _Label4@Exp
_Label2@Exp:
	mov	eax, DWORD PTR _i_1[ebp]
	add	eax, 1
	mov	DWORD PTR _i_1[ebp], eax
_Label4@Exp:
	cmp	DWORD PTR _i_1[ebp], 10			; 0000000aH
	jae	SHORT _Label3@Exp
	movsd	xmm0, QWORD PTR _x_[ebp]
	mulsd	xmm0, QWORD PTR _x_[ebp]
	movsd	QWORD PTR _x_[ebp], xmm0
	jmp	SHORT _Label2@Exp
_Label3@Exp:
;return x;
	fld	QWORD PTR _x_[ebp]
_Label1@Exp:
	mov	esp, ebp
	pop	ebp
	ret	0
_Exp	ENDP
_TEXT	ENDS
;------------------------------------------------------------;
;							字符串							；
;------------------------------------------------------------;
strlen proc ;eax:字符串地址;eax 字符串长度
    lea edx,[eax+1]
_strlen_loop:
    mov cl,[eax]
    inc eax
    test cl,cl
    jne SHORT _strlen_loop
    sub eax,edx
    ret
strlen endp
;字符串转数字
.code
atoi proc;eax字符串地址
	push ebx
	push ecx
	push edx

	mov ebx,eax
	cmp byte ptr [ebx],2DH
    jne SHORT _atoi_int_nonnegative
		mov edx,-1
		inc ebx ; 去掉负号
	_atoi_int_nonnegative:
	xor eax, eax ; zero a "result so far"
	atoi_top:
	movzx ecx, byte ptr [ebx] ; get a character
	inc ebx ; ready for next one
	cmp ecx, '0' ; valid?
	jb atoi_done
	cmp ecx, '9'
	ja atoi_done
	sub ecx, '0' ; "convert" character to number
	imul eax, 10 ; multiply "result so far" by ten
	add eax, ecx ; add in current digit
	jmp atoi_top ; until done
	atoi_done:

	cmp edx,0
    jge SHORT _atoi_int_nonnegative2
		neg eax ;变回负数
	_atoi_int_nonnegative2:

	pop edx
	pop ecx
	pop ebx
	ret
atoi endp
;输出单个字符
.data?
    align 4
    __putchar_size dd ?
.code
putchar	PROC						;  

	push	ebp
	mov	ebp, esp
	push ebx

	mov eax,ebp
	mov ebx,1
	add eax,8

	invoke WriteConsoleA,
        __stdout_handle,       ;hConsoleOutput
        eax,              ;lpBuffer
        ebx, ;nNumberOfCharsToWrite
        offset __putchar_size,   ;lpNumberOfCharsWritten
        0                      ;lpReserved

	pop ebx
	pop	ebp
	ret	0
putchar	ENDP

.data
	align 4
	__int_buffer dd 16 dup(0)
.code
itoa PROC
	push ebx
	push ecx
	push edx
    mov ebx,eax ;暂存
    ;判断正负
	mov edx,0
	cmp ebx,0
    jge SHORT _itoa_int_nonnegative
		mov edx,-1
		neg ebx ;变为正数
	_itoa_int_nonnegative:
	push edx
	mov ecx,offset __int_buffer + 14 ;字符串地址
	;除法准备
	mov eax,ebx
	mov ebx,10
	_itoa_int_int2ascii:
		mov edx,0
		div ebx
		or dl,30H ;转为ascii字符
		mov [ecx],dl
		dec ecx
		test eax,eax
	jne SHORT _itoa_int_int2ascii
	;添加负号
	pop edx
	cmp edx,0
	jge SHORT _itoa_no_sign
		mov byte ptr [ecx],2DH;负号
		dec ecx
	_itoa_no_sign:
	inc ecx
	mov eax,ecx

	pop edx
	pop ecx
	pop ebx
	ret
itoa ENDP
.data
	align 4
	__double_Buffer dd 32 dup(0)
.code
	__double_to_char_tv298 = -12						; size = 4
	__double_to_char_units = -8						; size = 4
	__double_to_char_decimals = -4					; size = 4
;double变字符串
dtoa PROC					;  
	push ebx
	push ecx
	push edx
	push	ebp
	mov	ebp, esp
	movaps	xmm2, xmm0
	xorps	xmm3, xmm3
	sub	esp, 12					; 0000000cH
	mov	ecx, 100				; 00000064H
	comisd	xmm3, xmm2
	jbe	SHORT _Label4@double_to_
	mulsd	xmm0, QWORD PTR real__1
	movaps	xmm1, xmm2
	mulsd	xmm1, QWORD PTR real__100
	cvttsd2si eax, xmm1
	jmp	SHORT _Label13@double_to_
_Label4@double_to_:
	mulsd	xmm0, QWORD PTR real_100
	cvttsd2si eax, xmm0
	movaps	xmm0, xmm2
_Label13@double_to_:
	cdq
	idiv	ecx
	cvttsd2si eax, xmm0
	mov	DWORD PTR __double_to_char_decimals[ebp], edx
	push	ebx
	push	esi
	mov	esi, OFFSET __double_Buffer+27
	mov	BYTE PTR __double_Buffer+27, 46		; 0000002eH
	mov	DWORD PTR __double_to_char_units[ebp], eax
	mov	eax, -858993459				; cccccccdH
	mul	edx
	mov	eax, DWORD PTR __double_to_char_decimals[ebp]
	shr	edx, 3
	mov	cl, dl
	mov	DWORD PTR __double_to_char_tv298[ebp], edx
	shl	cl, 2
	lea	ebx, DWORD PTR [ecx+edx]
	mov	ecx, DWORD PTR __double_to_char_tv298[ebp]
	add	bl, bl
	sub	al, bl
	add	al, 48					; 00000030H
	mov	BYTE PTR __double_Buffer+29, al
	mov	eax, -858993459				; cccccccdH
	mul	edx
	shr	edx, 3
	mov	al, dl
	shl	dl, 2
	add	al, dl
	cvttsd2si edx, xmm0
	add	al, al
	sub	cl, al
	add	cl, 48					; 00000030H
	mov	BYTE PTR __double_Buffer+28, cl
	test	edx, edx
	jle	SHORT _Label3@double_to_
_LL2@double_to_:
	mov	eax, 1717986919				; 66666667H
	dec	esi
	imul	edx
	sar	edx, 2
	mov	ebx, edx
	shr	ebx, 31					; 0000001fH
	add	ebx, edx
	mov	edx, DWORD PTR __double_to_char_units[ebp]
	mov	al, bl
	shl	al, 2
	lea	ecx, DWORD PTR [eax+ebx]
	add	cl, cl
	sub	dl, cl
	add	dl, 48					; 00000030H
	mov	BYTE PTR [esi], dl
	mov	edx, ebx
	mov	DWORD PTR __double_to_char_units[ebp], edx
	test	edx, edx
	jg	SHORT _LL2@double_to_
_Label3@double_to_:
	comisd	xmm3, xmm2
	jbe	SHORT _Label12@double_to_
	mov	BYTE PTR [esi-1], 45			; 0000002dH
	lea	eax, DWORD PTR [esi-1]
	pop	esi

	pop	ebx
	mov	esp, ebp
	pop	ebp
	ret	0
_Label12@double_to_:
	mov	eax, esi
	pop	esi
	pop	ebx
	mov	esp, ebp
	pop	ebp
	pop edx
	pop ecx
	pop ebx
	ret	0
dtoa ENDP
;------------------------------------------------------------;
;						控制台输入输出							；
;------------------------------------------------------------;
.const
    align 4
    __println_ENDL db ENDL
.data?
    align 4
    __scan_size dd ?
.code
scan macro lpBuffer
	INVOKE ReadConsoleA, __stdout_handle, lpBuffer,
      BUFFER_SIZE, ADDR __scan_size, 0
	mov eax,__scan_size
endm

;print-输出指定长度的字符串
.data?
    align 4
    __print_size dd ?
.code
print macro lpBuffer,nNumberOfCharsToWrite ;字符串地址,字符串长度;eax 实际输出字节数
    invoke WriteConsoleA,
        __stdout_handle,       ;hConsoleOutput
        lpBuffer,              ;lpBuffer
        nNumberOfCharsToWrite, ;nNumberOfCharsToWrite
        offset __print_size,   ;lpNumberOfCharsWritten
        0                      ;lpReserved
    mov eax,__print_size	;返回输出长度
endm

;输出字符串直到末尾（最多1024字节）
.data?
    align 4
    __string_size dd ?
.code
WriteString proc ;eax字符串地址
	push ebx
	push ecx
	mov ebx,0
_prints_begin:
	cmp byte ptr [eax+ebx], 0
	je _prints_done
	add ebx,1
	jmp _prints_begin
_prints_done:
	print eax,ebx
	pop ecx
	pop ebx
	ret
WriteString endp
prints macro lpBuffer ;字符串地址,字符串长度;eax 实际输出字节数
	mov eax,lpBuffer
	call WriteString
endm

printi macro integer ;字符串地址,字符串长度;eax 实际输出字节数
	mov eax,integer
	call itoa
	call WriteString
endm

.code
println macro ;;eax 2
    print offset __println_ENDL,2
endm
;------------------------------------------------------------;
;						文件操作								；
;------------------------------------------------------------;
fopenR macro lpFilename ;文件名地址;eax 文件句柄或INVALID_HANDLE_VALUE
    invoke CreateFileA,
        lpFilename,            ;lpFilename
        GENERIC_READ,          ;dwDesiredAccess
        FILE_SHARE_READ,       ;dwShareMode
        NULL,                  ;lpSecurityAttributes
        OPEN_EXISTING,         ;dwCreationDisposition
        FILE_ATTRIBUTE_NORMAL, ;dwFlagsAndAttributes
        0                      ;hTemplateFile
endm

fopenW macro lpFilename ;文件名地址;eax 文件句柄或INVALID_HANDLE_VALUE
    invoke CreateFileA,
        lpFilename,            ;lpFilename
        GENERIC_WRITE,         ;dwDesiredAccess
        DO_NOT_SHARE,          ;dwShareMode
        NULL,                  ;lpSecurityAttributes
        CREATE_ALWAYS,         ;dwCreationDisposition
        FILE_ATTRIBUTE_NORMAL, ;dwFlagsAndAttributes
        0                      ;hTemplateFile
endm

.data?
    align 4
    __fread_size dd ?
.code
fread macro lpBuffer,nNumberOfBytesToRead,hFile ;缓冲区地址,读取字节数,文件句柄;eax 实际读取字节数
    invoke ReadFile,
        hFile,                ;hFile
        lpBuffer,             ;lpBuffer
        nNumberOfBytesToRead, ;nNumberOfBytesToRead
        offset __fread_size,  ;lpNumberOfBytesRead
        0                     ;lpOverlapped
    mov eax,__fread_size
endm

.data?
    align 4
    __fwrite_size dd ?
fwrite macro lpBuffer,nNumberOfBytesToWrite,hFile ;缓冲区地址,写入字节数,文件句柄;eax 实际写入字节数
    invoke WriteFile,
        hFile,                 ;hFile
        lpBuffer,              ;lpBuffer
        nNumberOfBytesToWrite, ;nNumberOfBytesToWrite
        offset __fwrite_size,  ;lpNumberOfBytesWritten
        0                      ;lpOverlapped
    mov eax,__fwrite_size
endm

fclose macro hObject ;文件句柄;eax 文件关闭成功与否
    invoke CloseHandle,
        hObject         ;hObject
endm
;------------------------------------------------------------;
;							数据读取							；
;------------------------------------------------------------;
TRAIN_SIZE            = 60000
T10K_SIZE             = 10000
IMAGE_ROWS            = 28
IMAGE_COLUMNS         = 28
IMAGE_SIZE            = 784
BUFFER_SIZE           = 512
.const
train_images DB 'train-images.idx3-ubyte',00H
align 4
train_labels DB 'train-labels.idx1-ubyte',00H

align 4
s____precision_ DB '   precision:'
S____PRECISION__LEN = 13
align 4
s_Read_ DB 'Readed '
S_READ__LEN = 7
align 4
s__images_from_ DB ' images.  '
S__IMAGES_FROM__LEN = 8
align 4
s__labels_from_ DB ' labels.  '
S__LABELS_FROM__LEN = 8
align 4
s_dot_n db '.',ENDL
S_DOT_N_LEN = 3

.data?
	align 4
	buffer DD ?
	_labels DD ?
	_images DD ?
	images_num DD ?
.code
;翻转字节
reverse_int macro ;eax:整数;eax 翻转后的整数
    xchg ah,al
    rol eax,16
    xchg ah,al
ENDM
;
;读lable
__READ_MNIST_LABELS_LABELS = -8
__READ_MNIST_LABELS_N = -4
read_mnist_labels PROC ;ecx:文件名指针filename,edx:标签数组地址_labels;
    push ebp
    mov ebp,esp
    push ecx
    push ecx
    push ebx
    push edi
    mov ebx,ecx
    mov DWORD PTR __READ_MNIST_LABELS_LABELS[ebp],edx

    ;open file
    fopenR ebx
    mov edi,eax
    cmp edi,INVALID_HANDLE_VALUE
    je _read_mnist_labels_fopen_failed

    push esi
    print OFFSET s_Read_,S_READ__LEN
    
    ;read magic number
    lea eax,DWORD PTR __READ_MNIST_LABELS_N[ebp]
    fread eax,4,edi

    ;read number of _labels
    lea eax,DWORD PTR __READ_MNIST_LABELS_N[ebp]
    fread eax,4,edi

    ;reverse int and print
    mov eax,DWORD PTR __READ_MNIST_LABELS_N[ebp]
    reverse_int
    mov DWORD PTR __READ_MNIST_LABELS_N[ebp],eax
    printi eax

    ;read _labels
    fread _labels,DWORD PTR __READ_MNIST_LABELS_N[ebp],edi

    fclose edi

    print OFFSET s__labels_from_, S__LABELS_FROM__LEN
	println
    pop esi
_read_mnist_labels_fopen_failed:
    pop edi
    pop ebx
    leave
    ret
read_mnist_labels ENDP
;
;读取图像
__READ_MNIST_IMAGES_IMAGES = -32
__READ_MNIST_IMAGES_I = -28
__READ_MNIST_IMAGES_FILENAME = -28
__READ_MNIST_IMAGES_PO_IMAGES_I = -24 ;_images[i]-_images
__READ_MNIST_IMAGES_P = -20
__READ_MNIST_IMAGES_J = -16
__READ_MNIST_IMAGES_N_COLS = -12
__READ_MNIST_IMAGES_N_ROWS = -8
__READ_MNIST_IMAGES_N = -4
read_mnist_images PROC ;ecx:文件名指针filename,edx:图像数组地址_images;eax ?
    push ebp
    mov ebp,esp
    sub esp,32 ;temporary variables
    push ebx
    mov eax,ecx
    mov DWORD PTR __READ_MNIST_IMAGES_IMAGES[ebp],edx
    mov DWORD PTR __READ_MNIST_IMAGES_FILENAME[ebp],eax
    
    ;open file
    fopenR eax
    mov ebx,eax
    cmp ebx,INVALID_HANDLE_VALUE
    je _read_mnist_images_fopen_fail

    push esi
    push edi
    
    print OFFSET s_Read_,S_READ__LEN

    ;read magic number
    lea eax,DWORD PTR __READ_MNIST_IMAGES_N[ebp]
    push 4
    pop esi
    fread eax,esi,ebx

    ;read number of _images
    lea eax,DWORD PTR __READ_MNIST_IMAGES_N[ebp]
    fread eax,esi,ebx

    ;read number of rows
    lea eax,DWORD PTR __READ_MNIST_IMAGES_N_ROWS[ebp]
    fread eax,esi,ebx

    ;read number of cols
    lea eax,DWORD PTR __READ_MNIST_IMAGES_N_COLS[ebp]
    fread eax,esi,ebx

    ;reverse int and print
    mov eax,DWORD PTR __READ_MNIST_IMAGES_N[ebp]
    reverse_int
    mov DWORD PTR __READ_MNIST_IMAGES_N[ebp],eax
	mov _image_number,eax
    printi eax

    ;reverse int
    mov eax,DWORD PTR __READ_MNIST_IMAGES_N_ROWS[ebp]
    reverse_int
    mov DWORD PTR __READ_MNIST_IMAGES_N_ROWS[ebp],eax
	mov _n_rows,eax

    ;reverse int
    mov eax,DWORD PTR __READ_MNIST_IMAGES_N_COLS[ebp]
    reverse_int
    mov DWORD PTR __READ_MNIST_IMAGES_N_COLS[ebp],eax
	mov _n_cols,eax

    ;read _images
    mov eax,DWORD PTR __READ_MNIST_IMAGES_N_COLS[ebp]
    imul eax,DWORD PTR __READ_MNIST_IMAGES_N_ROWS[ebp]
    imul eax,DWORD PTR __READ_MNIST_IMAGES_N[ebp]
    fread _images,eax,ebx

    fclose ebx

    print OFFSET s__images_from_,S__IMAGES_FROM__LEN
	println

_read_mnist_images_loop_i_end:

    mov eax,DWORD PTR __READ_MNIST_IMAGES_N[ebp]
    pop edi
    pop esi
    jmp SHORT _read_mnist_images_end
_read_mnist_images_fopen_fail:
    or eax,-1
_read_mnist_images_end:
    pop ebx
    leave
    ret
read_mnist_images ENDP

;------------------------------------------------------------;
;							神经网络							；
;------------------------------------------------------------;
.code
;
;卷积并池化
_TEXT	SEGMENT
_j_1 = -32						; size = 4
_i_2 = -28						; size = 4
_j_3 = -24						; size = 4
_i_4 = -20						; size = 4
_y_5 = -16						; size = 4
_x_6 = -12						; size = 4
_y_7 = -8						; size = 4
_x_8 = -4						; size = 4
_il_ = 8						; size = 4
_ol_ = 12						; size = 4
_filter_ = 16						; size = 4
_ConvAndPool PROC					;  
;void ConvAndPool(double il[30][30], double ol[14][14], double filter[5][5])
	push	ebp
	mov	ebp, esp
	sub	esp, 32					; 00000020H
	push	esi
	push	edi
;卷积
;REP(x, 28)REP(y, 28) {
	mov	DWORD PTR _x_8[ebp], 0
	jmp	SHORT _Label4@ConvAndPoo
_Label2@ConvAndPoo:
	mov	eax, DWORD PTR _x_8[ebp]
	add	eax, 1
	mov	DWORD PTR _x_8[ebp], eax
_Label4@ConvAndPoo:
	cmp	DWORD PTR _x_8[ebp], 28			; 0000001cH
	jae	_Label3@ConvAndPoo
	mov	DWORD PTR _y_7[ebp], 0
	jmp	SHORT _Label7@ConvAndPoo
_Label5@ConvAndPoo:
	mov	ecx, DWORD PTR _y_7[ebp]
	add	ecx, 1
	mov	DWORD PTR _y_7[ebp], ecx
_Label7@ConvAndPoo:
	cmp	DWORD PTR _y_7[ebp], 28			; 0000001cH
	jae	_Label6@ConvAndPoo
	;temp_Pool[x][y] = 0;
		imul	edx, DWORD PTR _x_8[ebp], 224
		mov	eax, DWORD PTR _y_7[ebp]
		xorps	xmm0, xmm0
		movsd	QWORD PTR _temp_Pool[edx+eax*8], xmm0
	;REP(i, 5)REP(j, 5)
		mov	DWORD PTR _i_4[ebp], 0
	jmp	SHORT _Label10@ConvAndPoo
_Label8@ConvAndPoo:
	mov	ecx, DWORD PTR _i_4[ebp]
	add	ecx, 1
	mov	DWORD PTR _i_4[ebp], ecx
_Label10@ConvAndPoo:
	cmp	DWORD PTR _i_4[ebp], 5
	jae	SHORT _Label9@ConvAndPoo
	mov	DWORD PTR _j_3[ebp], 0
	jmp	SHORT _Label13@ConvAndPoo
_Label11@ConvAndPoo:
	mov	edx, DWORD PTR _j_3[ebp]
	add	edx, 1
	mov	DWORD PTR _j_3[ebp], edx
_Label13@ConvAndPoo:
	cmp	DWORD PTR _j_3[ebp], 5
	jae	SHORT _Label12@ConvAndPoo
	;和卷积核相乘
	;temp_Pool[x][y] += il[x + i][y + j] * filter[i][j];
		imul	eax, DWORD PTR _x_8[ebp], 224
		mov	ecx, DWORD PTR _x_8[ebp]
		add	ecx, DWORD PTR _i_4[ebp]
		imul	edx, ecx, 240
		add	edx, DWORD PTR _il_[ebp]
		mov	ecx, DWORD PTR _y_7[ebp]
		add	ecx, DWORD PTR _j_3[ebp]
		imul	esi, DWORD PTR _i_4[ebp], 40
		add	esi, DWORD PTR _filter_[ebp]
		mov	edi, DWORD PTR _j_3[ebp]
		movsd	xmm0, QWORD PTR [edx+ecx*8]
		mulsd	xmm0, QWORD PTR [esi+edi*8]
		mov	edx, DWORD PTR _y_7[ebp]
		addsd	xmm0, QWORD PTR _temp_Pool[eax+edx*8]
		imul	eax, DWORD PTR _x_8[ebp], 224
		mov	ecx, DWORD PTR _y_7[ebp]
		movsd	QWORD PTR _temp_Pool[eax+ecx*8], xmm0
	jmp	SHORT _Label11@ConvAndPoo
_Label12@ConvAndPoo:
	jmp	SHORT _Label8@ConvAndPoo
_Label9@ConvAndPoo:
;激活函数
;temp_Pool[x][y] = Relu(temp_Pool[x][y]);
	imul	edx, DWORD PTR _x_8[ebp], 224
	mov	eax, DWORD PTR _y_7[ebp]
	sub	esp, 8
	movsd	xmm0, QWORD PTR _temp_Pool[edx+eax*8]
	movsd	QWORD PTR [esp], xmm0
	call	_Relu
	add	esp, 8
	imul	ecx, DWORD PTR _x_8[ebp], 224
	mov	edx, DWORD PTR _y_7[ebp]
	fstp	QWORD PTR _temp_Pool[ecx+edx*8]
	jmp	_Label5@ConvAndPoo
_Label6@ConvAndPoo:
	jmp	_Label2@ConvAndPoo
_Label3@ConvAndPoo:
;池化
;REP(x, 12)REP(y, 12) 
	mov	DWORD PTR _x_6[ebp], 0
	jmp	SHORT _Label16@ConvAndPoo
_Label14@ConvAndPoo:
	mov	eax, DWORD PTR _x_6[ebp]
	add	eax, 1
	mov	DWORD PTR _x_6[ebp], eax
_Label16@ConvAndPoo:
	cmp	DWORD PTR _x_6[ebp], 12			; 0000000cH
	jae	_Label15@ConvAndPoo
	mov	DWORD PTR _y_5[ebp], 0
	jmp	SHORT _Label19@ConvAndPoo
_Label17@ConvAndPoo:
	mov	ecx, DWORD PTR _y_5[ebp]
	add	ecx, 1
	mov	DWORD PTR _y_5[ebp], ecx
_Label19@ConvAndPoo:
	cmp	DWORD PTR _y_5[ebp], 12			; 0000000cH
	jae	_Label18@ConvAndPoo
	;ol[x][y] = 0;
		imul	edx, DWORD PTR _x_6[ebp], 112
		add	edx, DWORD PTR _ol_[ebp]
		mov	eax, DWORD PTR _y_5[ebp]
		xorps	xmm0, xmm0
		movsd	QWORD PTR [edx+eax*8], xmm0
;REP(i, 2)REP(j, 2) 
	mov	DWORD PTR _i_2[ebp], 0
	jmp	SHORT _Label22@ConvAndPoo
_Label20@ConvAndPoo:
	mov	ecx, DWORD PTR _i_2[ebp]
	add	ecx, 1
	mov	DWORD PTR _i_2[ebp], ecx
_Label22@ConvAndPoo:
	cmp	DWORD PTR _i_2[ebp], 2
	jae	SHORT _Label21@ConvAndPoo
	mov	DWORD PTR _j_1[ebp], 0
	jmp	SHORT _Label25@ConvAndPoo
_Label23@ConvAndPoo:
	mov	edx, DWORD PTR _j_1[ebp]
	add	edx, 1
	mov	DWORD PTR _j_1[ebp], edx
_Label25@ConvAndPoo:
	cmp	DWORD PTR _j_1[ebp], 2
	jae	SHORT _Label24@ConvAndPoo
	;取最大值
	;ol[x][y] = dMax(ol[x][y], temp_Pool[x * 2 + i][y * 2 + j]);
		mov	eax, DWORD PTR _x_6[ebp]
		mov	ecx, DWORD PTR _i_2[ebp]
		lea	edx, DWORD PTR [ecx+eax*2]
		imul	eax, edx, 224
		mov	ecx, DWORD PTR _y_5[ebp]
		mov	edx, DWORD PTR _j_1[ebp]
		lea	ecx, DWORD PTR [edx+ecx*2]
		sub	esp, 8
		movsd	xmm0, QWORD PTR _temp_Pool[eax+ecx*8]
		movsd	QWORD PTR [esp], xmm0
		imul	edx, DWORD PTR _x_6[ebp], 112
		add	edx, DWORD PTR _ol_[ebp]
		mov	eax, DWORD PTR _y_5[ebp]
		sub	esp, 8
		movsd	xmm0, QWORD PTR [edx+eax*8]
		movsd	QWORD PTR [esp], xmm0
		call	_dMax
		add	esp, 16					; 00000010H
		imul	ecx, DWORD PTR _x_6[ebp], 112
		add	ecx, DWORD PTR _ol_[ebp]
		mov	edx, DWORD PTR _y_5[ebp]
		fstp	QWORD PTR [ecx+edx*8]
	jmp	SHORT _Label23@ConvAndPoo
_Label24@ConvAndPoo:
	jmp	SHORT _Label20@ConvAndPoo
_Label21@ConvAndPoo:
	jmp	_Label17@ConvAndPoo
_Label18@ConvAndPoo:
	jmp	_Label14@ConvAndPoo
_Label15@ConvAndPoo:
	pop	edi
	pop	esi
	mov	esp, ebp
	pop	ebp
	ret	0
_ConvAndPool ENDP
_TEXT	ENDS
;
;输入全连接层
_TEXT	SEGMENT
_cnt_ = -16						; size = 4
_j_1 = -12						; size = 4
_i_2 = -8						; size = 4
_x_3 = -4						; size = 4
_ol_ = 8						; size = 4
_fl_ = 12						; size = 4
_FullyInput PROC	
;void FullyInput(struct OutLayer* ol, double* fl)
	push	ebp
	mov	ebp, esp
	sub	esp, 16					; 00000010H
	push	esi
;int cnt = 0;
	mov	DWORD PTR _cnt_[ebp], 0
;REP(x, filterNum) 
	mov	DWORD PTR _x_3[ebp], 0
	jmp	SHORT _Label4@FullyInput
_Label2@FullyInput:
	mov	eax, DWORD PTR _x_3[ebp]
	add	eax, 1
	mov	DWORD PTR _x_3[ebp], eax
_Label4@FullyInput:
	cmp	DWORD PTR _x_3[ebp], 5
	jae	SHORT _Label3@FullyInput
	;遍历池化输出
	;REP(i, 14)REP(j, 14) 
		mov	DWORD PTR _i_2[ebp], 0
		jmp	SHORT _Label7@FullyInput
	_Label5@FullyInput:
		mov	ecx, DWORD PTR _i_2[ebp]
		add	ecx, 1
		mov	DWORD PTR _i_2[ebp], ecx
	_Label7@FullyInput:
		cmp	DWORD PTR _i_2[ebp], 14			; 0000000eH
		jae	SHORT _Label6@FullyInput
		mov	DWORD PTR _j_1[ebp], 0
		jmp	SHORT _Label10@FullyInput
	_Label8@FullyInput:
		mov	edx, DWORD PTR _j_1[ebp]
		add	edx, 1
		mov	DWORD PTR _j_1[ebp], edx
	_Label10@FullyInput:
		cmp	DWORD PTR _j_1[ebp], 14			; 0000000eH
		jae	SHORT _Label9@FullyInput
		;展开为数组
		;fl[cnt++] = ol[x].w[i][j];
			imul	eax, DWORD PTR _x_3[ebp], 1568
			add	eax, DWORD PTR _ol_[ebp]
			imul	ecx, DWORD PTR _i_2[ebp], 112
			add	eax, ecx
			mov	edx, DWORD PTR _cnt_[ebp]
			mov	ecx, DWORD PTR _fl_[ebp]
			mov	esi, DWORD PTR _j_1[ebp]
			movsd	xmm0, QWORD PTR [eax+esi*8]
			movsd	QWORD PTR [ecx+edx*8], xmm0
			mov	edx, DWORD PTR _cnt_[ebp]
			add	edx, 1
			mov	DWORD PTR _cnt_[ebp], edx
			jmp	SHORT _Label8@FullyInput
	_Label9@FullyInput:
		jmp	SHORT _Label5@FullyInput
	_Label6@FullyInput:		jmp	SHORT _Label2@FullyInput
	_Label3@FullyInput:
	;CNN.len = cnt;
		mov	eax, DWORD PTR _cnt_[ebp]
		mov	DWORD PTR _CNN+104280, eax
	pop	esi
	mov	esp, ebp
	pop	ebp
	ret	0
_FullyInput ENDP
_TEXT	ENDS
;
;全连接
_TEXT	SEGMENT
tv184 = -52						; size = 8
tv174 = -44						; size = 8
_sum_ = -36						; size = 8
_max_ = -28						; size = 8
_i_1 = -20						; size = 4
_i_2 = -16						; size = 4
_i_3 = -12						; size = 4
_j_4 = -8						; size = 4
_i_5 = -4						; size = 4
_fl_ = 8						; size = 4
_out_ = 12						; size = 4
_FullyMul PROC
;void FullyMul(double* fl, double* out)
	push	ebp
	mov	ebp, esp
	sub	esp, 52					; 00000034H
	push	esi
;全连接
;REP(i, 10)
	mov	DWORD PTR _i_5[ebp], 0
	jmp	SHORT _Label4@FullyMul
_Label2@FullyMul:
	mov	eax, DWORD PTR _i_5[ebp]
	add	eax, 1
	mov	DWORD PTR _i_5[ebp], eax
_Label4@FullyMul:
	cmp	DWORD PTR _i_5[ebp], 10			; 0000000aH
	jae	SHORT _Label3@FullyMul
	;out[i] = 0;
		mov	ecx, DWORD PTR _i_5[ebp]
		mov	edx, DWORD PTR _out_[ebp]
		xorps	xmm0, xmm0
		movsd	QWORD PTR [edx+ecx*8], xmm0
	;REP(j, CNN.len) {
		mov	DWORD PTR _j_4[ebp], 0
		jmp	SHORT _Label7@FullyMul
	_Label5@FullyMul:
		mov	eax, DWORD PTR _j_4[ebp]
		add	eax, 1
		mov	DWORD PTR _j_4[ebp], eax
	_Label7@FullyMul:
		mov	ecx, DWORD PTR _j_4[ebp]
		cmp	ecx, DWORD PTR _CNN+104280
		jae	SHORT _Label6@FullyMul
		;和权重相乘并相加
		;out[i] += fl[j] * CNN.w[i][j];
			imul	edx, DWORD PTR _i_5[ebp], 8000
			mov	eax, DWORD PTR _j_4[ebp]
			mov	ecx, DWORD PTR _fl_[ebp]
			mov	esi, DWORD PTR _j_4[ebp]
			movsd	xmm0, QWORD PTR [ecx+eax*8]
			mulsd	xmm0, QWORD PTR _CNN[edx+esi*8+24040]
			mov	edx, DWORD PTR _i_5[ebp]
			mov	eax, DWORD PTR _out_[ebp]
			addsd	xmm0, QWORD PTR [eax+edx*8]
			mov	ecx, DWORD PTR _i_5[ebp]
			mov	edx, DWORD PTR _out_[ebp]
			movsd	QWORD PTR [edx+ecx*8], xmm0
		jmp	SHORT _Label5@FullyMul
	_Label6@FullyMul:
	jmp	SHORT _Label2@FullyMul
_Label3@FullyMul:
;softMax归一化
;double max = -1e9;
	movsd	xmm0, QWORD PTR real__1E9
	movsd	QWORD PTR _max_[ebp], xmm0
;double sum = 0;
	xorps	xmm0, xmm0
	movsd	QWORD PTR _sum_[ebp], xmm0
;取最大值
;REP(i, 10) max = dMax(max, out[i]);
	mov	DWORD PTR _i_2[ebp], 0
	jmp	SHORT _Label10@FullyMul
_Label8@FullyMul:
	mov	eax, DWORD PTR _i_2[ebp]
	add	eax, 1
	mov	DWORD PTR _i_2[ebp], eax
	_Label10@FullyMul:
		cmp	DWORD PTR _i_2[ebp], 10			; 0000000aH
		jae	SHORT _Label9@FullyMul
		mov	ecx, DWORD PTR _i_2[ebp]
		mov	edx, DWORD PTR _out_[ebp]
		sub	esp, 8
		movsd	xmm0, QWORD PTR [edx+ecx*8]
		movsd	QWORD PTR [esp], xmm0
		sub	esp, 8
		movsd	xmm0, QWORD PTR _max_[ebp]
		movsd	QWORD PTR [esp], xmm0
		call	_dMax
		add	esp, 16					; 00000010H
		fstp	QWORD PTR _max_[ebp]
	jmp	SHORT _Label8@FullyMul
_Label9@FullyMul:
;求和Exp(out[i] - max)
;REP(i, 10) sum += Exp(out[i] - max);
	mov	DWORD PTR _i_1[ebp], 0
	jmp	SHORT _Label13@FullyMul
_Label11@FullyMul:
	mov	eax, DWORD PTR _i_1[ebp]
	add	eax, 1
	mov	DWORD PTR _i_1[ebp], eax
_Label13@FullyMul:
	cmp	DWORD PTR _i_1[ebp], 10			; 0000000aH
	jae	SHORT _Label12@FullyMul
		mov	ecx, DWORD PTR _i_1[ebp]
		mov	edx, DWORD PTR _out_[ebp]
		movsd	xmm0, QWORD PTR [edx+ecx*8]
		subsd	xmm0, QWORD PTR _max_[ebp]
		sub	esp, 8
		movsd	QWORD PTR [esp], xmm0
		call	_Exp
		add	esp, 8
		fstp	QWORD PTR tv174[ebp]
		movsd	xmm0, QWORD PTR tv174[ebp]
		addsd	xmm0, QWORD PTR _sum_[ebp]
		movsd	QWORD PTR _sum_[ebp], xmm0
		jmp	SHORT _Label11@FullyMul
	_Label12@FullyMul:
;使和=1
;REP(i, 10) out[i] = Exp(out[i] - max) / sum;
	mov	DWORD PTR _i_3[ebp], 0
	jmp	SHORT _Label16@FullyMul
_Label14@FullyMul:
	mov	eax, DWORD PTR _i_3[ebp]
	add	eax, 1
	mov	DWORD PTR _i_3[ebp], eax
_Label16@FullyMul:
	cmp	DWORD PTR _i_3[ebp], 10			; 0000000aH
	jae	SHORT _Label15@FullyMul
		mov	ecx, DWORD PTR _i_3[ebp]
		mov	edx, DWORD PTR _out_[ebp]
		movsd	xmm0, QWORD PTR [edx+ecx*8]
		subsd	xmm0, QWORD PTR _max_[ebp]
		sub	esp, 8
		movsd	QWORD PTR [esp], xmm0
		call	_Exp
		add	esp, 8
		fstp	QWORD PTR tv184[ebp]
		movsd	xmm0, QWORD PTR tv184[ebp]
		divsd	xmm0, QWORD PTR _sum_[ebp]
		mov	eax, DWORD PTR _i_3[ebp]
		mov	ecx, DWORD PTR _out_[ebp]
		movsd	QWORD PTR [ecx+eax*8], xmm0
	jmp	SHORT _Label14@FullyMul
_Label15@FullyMul:
	pop	esi
	mov	esp, ebp
	pop	ebp
	ret	0
_FullyMul ENDP
_TEXT	ENDS
;
;前向传播
_TEXT	SEGMENT
_i_1 = -16						; size = 4
_r_2 = -12						; size = 4
_c_3 = -8						; size = 4
_i_4 = -4						; size = 4
_index_ = 8						; size = 4
_ForwardPropagation PROC				;  
;void ForwardPropagation(int index)
	push	ebp
	mov	ebp, esp
	sub	esp, 16					; 00000010H
;输入数据
;REP(c, n_cols) REP(r, n_rows)
	mov	DWORD PTR _c_3[ebp], 0
	jmp	SHORT _Label4@ForwardPro
_Label2@ForwardPro:
	mov	eax, DWORD PTR _c_3[ebp]
	add	eax, 1
	mov	DWORD PTR _c_3[ebp], eax
_Label4@ForwardPro:
	mov	ecx, DWORD PTR _c_3[ebp]
	cmp	ecx, DWORD PTR _n_cols
	jae	_Label3@ForwardPro
	mov	DWORD PTR _r_2[ebp], 0
	jmp	SHORT _Label7@ForwardPro
_Label5@ForwardPro:
	mov	edx, DWORD PTR _r_2[ebp]
	add	edx, 1
	mov	DWORD PTR _r_2[ebp], edx
_Label7@ForwardPro:
	mov	eax, DWORD PTR _r_2[ebp]
	cmp	eax, DWORD PTR _n_rows
	jae	SHORT _Label6@ForwardPro
	;CNN.il.w[c][r] = PIX(index, c, r)/255.0;
		mov	ecx, DWORD PTR _index_[ebp]
		imul	ecx, DWORD PTR _n_rows
		imul	ecx, DWORD PTR _n_cols
		add	ecx, DWORD PTR _images
		mov	edx, DWORD PTR _c_3[ebp]
		imul	edx, DWORD PTR _n_rows
		add	ecx, DWORD PTR _r_2[ebp]
		movzx	eax, BYTE PTR [edx+ecx]
		cvtsi2sd xmm0, eax
		divsd	xmm0, QWORD PTR real_255
		imul	ecx, DWORD PTR _c_3[ebp], 240
		mov	edx, DWORD PTR _r_2[ebp]
		movsd	QWORD PTR _CNN[ecx+edx*8], xmm0
	;if (PIX(index, c, r) != 0) index += 0;
		mov	eax, DWORD PTR _index_[ebp]
		imul	eax, DWORD PTR _n_rows
		imul	eax, DWORD PTR _n_cols
		add	eax, DWORD PTR _images
		mov	ecx, DWORD PTR _c_3[ebp]
		imul	ecx, DWORD PTR _n_rows
		add	eax, DWORD PTR _r_2[ebp]
		movzx	edx, BYTE PTR [ecx+eax]
		test	edx, edx
		je	SHORT _Label14@ForwardPro
		mov	eax, DWORD PTR _index_[ebp]
		mov	DWORD PTR _index_[ebp], eax
_Label14@ForwardPro:
	jmp	_Label5@ForwardPro
_Label6@ForwardPro:
	jmp	_Label2@ForwardPro
_Label3@ForwardPro:
;卷积池化
;REP(i, filterNum)
		mov	DWORD PTR _i_1[ebp], 0
		jmp	SHORT _Label10@ForwardPro
	_Label8@ForwardPro:
		mov	ecx, DWORD PTR _i_1[ebp]
		add	ecx, 1
		mov	DWORD PTR _i_1[ebp], ecx
	_Label10@ForwardPro:
		cmp	DWORD PTR _i_1[ebp], 5
		jae	SHORT _Label9@ForwardPro
	; 237  : 		ConvAndPool(CNN.il.w, CNN.ol[i].w, CNN.filter[i].w);
		imul	edx, DWORD PTR _i_1[ebp], 200
		add	edx, OFFSET _CNN+15040
		push	edx
		imul	eax, DWORD PTR _i_1[ebp], 1568
		add	eax, OFFSET _CNN+7200
		push	eax
		push	OFFSET _CNN
		call	_ConvAndPool
		add	esp, 12					; 0000000cH
	jmp	SHORT _Label8@ForwardPro
_Label9@ForwardPro:
;全连接
;FullyInput(CNN.ol, CNN.FullyLayer);
	push	OFFSET _CNN+16040
	push	OFFSET _CNN+7200
	call	_FullyInput
	add	esp, 8
;FullyMul(CNN.FullyLayer, CNN.out);
	push	OFFSET _CNN+104040
	push	OFFSET _CNN+16040
	call	_FullyMul
	add	esp, 8
;REP(i, 10) 
		mov	DWORD PTR _i_4[ebp], 0
		jmp	SHORT _Label13@ForwardPro
	_Label11@ForwardPro:
		mov	ecx, DWORD PTR _i_4[ebp]
		add	ecx, 1
		mov	DWORD PTR _i_4[ebp], ecx
	_Label13@ForwardPro:
		cmp	DWORD PTR _i_4[ebp], 10			; 0000000aH
		jae	SHORT _Label12@ForwardPro
	;if (i == labels[index]) CNN.delta[i] = CNN.out[i] - 1.0;
			mov	edx, DWORD PTR _labels
			add	edx, DWORD PTR _index_[ebp]
			movzx	eax, BYTE PTR [edx]
			cmp	DWORD PTR _i_4[ebp], eax
			jne	SHORT _Label15@ForwardPro
			mov	ecx, DWORD PTR _i_4[ebp]
			movsd	xmm0, QWORD PTR _CNN[ecx*8+104040]
			subsd	xmm0, QWORD PTR real_1
			mov	edx, DWORD PTR _i_4[ebp]
			movsd	QWORD PTR _CNN[edx*8+104200], xmm0
			jmp	SHORT _Label16@ForwardPro
		_Label15@ForwardPro:
		;else CNN.delta[i] = CNN.out[i];
			mov	eax, DWORD PTR _i_4[ebp]
			mov	ecx, DWORD PTR _i_4[ebp]
			movsd	xmm0, QWORD PTR _CNN[ecx*8+104040]
			movsd	QWORD PTR _CNN[eax*8+104200], xmm0
		_Label16@ForwardPro:
		jmp	SHORT _Label11@ForwardPro
	_Label12@ForwardPro:
	mov	esp, ebp
	pop	ebp
	ret	0
_ForwardPropagation ENDP
_TEXT	ENDS
;
;反向传播
_TEXT	SEGMENT
_i_1 = -8						; size = 4
_j_2 = -4						; size = 4
_index_ = 8						; size = 4
_BackPropagation PROC					;  
;void BackPropagation(int index)
	push	ebp
	mov	ebp, esp
	sub	esp, 8
;REP(i, 14 * 14 * filterNum + 20)
		mov	DWORD PTR _i_1[ebp], 0
		jmp	SHORT _Label4@BackPropag
	_Label2@BackPropag:
		mov	eax, DWORD PTR _i_1[ebp]
		add	eax, 1
		mov	DWORD PTR _i_1[ebp], eax
	_Label4@BackPropag:
		cmp	DWORD PTR _i_1[ebp], 1000		; 000003e8H
		jae	SHORT _Label3@BackPropag
		;REP(j, 10) {
			mov	DWORD PTR _j_2[ebp], 0
			jmp	SHORT _Label7@BackPropag
		_Label5@BackPropag:
			mov	ecx, DWORD PTR _j_2[ebp]
			add	ecx, 1
			mov	DWORD PTR _j_2[ebp], ecx
		_Label7@BackPropag:
			cmp	DWORD PTR _j_2[ebp], 10			; 0000000aH
			jae	SHORT _Label6@BackPropag
		;CNN.w[j][i] -= eta * CNN.delta[j] * CNN.FullyLayer[i];
		
			imul	edx, DWORD PTR _j_2[ebp], 8000
			mov	eax, DWORD PTR _j_2[ebp]
			movsd	xmm0, QWORD PTR _eta
			mulsd	xmm0, QWORD PTR _CNN[eax*8+104200]
			mov	ecx, DWORD PTR _i_1[ebp]
			mulsd	xmm0, QWORD PTR _CNN[ecx*8+16040]
			mov	eax, DWORD PTR _i_1[ebp]
			movsd	xmm1, QWORD PTR _CNN[edx+eax*8+24040]
			subsd	xmm1, xmm0
			imul	ecx, DWORD PTR _j_2[ebp], 8000
			mov	edx, DWORD PTR _i_1[ebp]
			movsd	QWORD PTR _CNN[ecx+edx*8+24040], xmm1
	jmp	SHORT _Label5@BackPropag
_Label6@BackPropag:
	jmp	SHORT _Label2@BackPropag
_Label3@BackPropag:
	mov	esp, ebp
	pop	ebp
	ret	0
_BackPropagation ENDP
_TEXT	ENDS
;
;训练
.data
	__Train_complete DB 'Train complete.', 0aH, 00H
	__Train_STPE DB 'STPE: ', 00H
	__Train_RATE DB ', RATE: ', 00H
.code
;	  _Train
_TEXT	SEGMENT
_k_4 = -48						; size = 8
_p_1 = -44						; size = 8
_max_2 = -36						; size = 8
_times_ = -28						; size = 4
_ans_3 = -24						; size = 4
_cnt_4 = -20						; size = 4
_index_5 = -16						; size = 4
_j_6 = -12						; size = 4
_i_7 = -8						; size = 4
_k_8 = -4						; size = 4
_Train	PROC						;  
	push	ebp
	mov	ebp, esp
	sub	esp, 48					; 0000002cH
;int times = 100;
;定义迭代次数
	mov	DWORD PTR _times_[ebp], 100		; 00000064H
;REP(i, times) 
		mov	DWORD PTR _i_7[ebp], 0
		jmp	SHORT _Label4@Train
	_Label2@Train:
		mov	eax, DWORD PTR _i_7[ebp]
		add	eax, 1
		mov	DWORD PTR _i_7[ebp], eax
	_Label4@Train:
		mov	ecx, DWORD PTR _i_7[ebp]
		cmp	ecx, DWORD PTR _times_[ebp]
		jae	_Label3@Train
	;int cnt = 0;
	;计算成功次数
		mov	DWORD PTR _cnt_4[ebp], 0
	;REP(j, 3000) 
		mov	DWORD PTR _j_6[ebp], 0
		jmp	SHORT _Label7@Train
	_Label5@Train:
		mov	edx, DWORD PTR _j_6[ebp]
		add	edx, 1
		mov	DWORD PTR _j_6[ebp], edx
	_Label7@Train:
		cmp	DWORD PTR _j_6[ebp], 3000		; 00000bb8H
		jae	_Label6@Train
		;int index = Rand(image_number);
			mov	eax, DWORD PTR _image_number
			push	eax
			call	_Rand
			add	esp, 4
			mov	DWORD PTR _index_5[ebp], eax
		;ForwardPropagation(index);
			mov	ecx, DWORD PTR _index_5[ebp]
			push	ecx
			call	_ForwardPropagation
			add	esp, 4
		;BackPropagation(index)
			mov	edx, DWORD PTR _index_5[ebp]
			push	edx
			call	_BackPropagation
			add	esp, 4
		;//验证
		;int ans = 0;
			mov	DWORD PTR _ans_3[ebp], 0
		;double max = -1e9;
			movsd	xmm0, QWORD PTR real__1E9
			movsd	QWORD PTR _max_2[ebp], xmm0
		;REP(k, 10)
			mov	DWORD PTR _k_8[ebp], 0
			jmp	SHORT _Label10@Train
		_Label8@Train:
			mov	eax, DWORD PTR _k_8[ebp]
			add	eax, 1
			mov	DWORD PTR _k_8[ebp], eax
		_Label10@Train:
			cmp	DWORD PTR _k_8[ebp], 10			; 0000000aH
			jae	SHORT _Label9@Train
			;if (max < CNN.out[k])
				mov	ecx, DWORD PTR _k_8[ebp]
				movsd	xmm0, QWORD PTR _CNN[ecx*8+104040]
				comisd	xmm0, QWORD PTR _max_2[ebp]
				jbe	SHORT _Label11@Train
			;ans = k;
				mov	edx, DWORD PTR _k_8[ebp]
				mov	DWORD PTR _ans_3[ebp], edx
			;max = CNN.out[k];
				mov	eax, DWORD PTR _k_8[ebp]
				movsd	xmm0, QWORD PTR _CNN[eax*8+104040]
				movsd	QWORD PTR _max_2[ebp], xmm0
			_Label11@Train:
	jmp	SHORT _Label8@Train
	_Label9@Train:
	;if (ans == labels[index]) cnt++;
			mov	eax, DWORD PTR _ans_3[ebp]
			mov	ecx, DWORD PTR _labels
			add	ecx, DWORD PTR _index_5[ebp]
			movzx	edx, BYTE PTR [ecx]
			cmp	DWORD PTR _ans_3[ebp], edx
			jne	SHORT _Label12@Train
			mov	eax, DWORD PTR _cnt_4[ebp]
			add	eax, 1
			mov	DWORD PTR _cnt_4[ebp], eax
	_Label12@Train:
		jmp	_Label5@Train
	_Label6@Train:
	;计算成功率
	;double p = (1.0 * cnt) / 3000 * 100;
		cvtsi2sd xmm0, DWORD PTR _cnt_4[ebp]
		mulsd	xmm0, QWORD PTR real_1
		divsd	xmm0, QWORD PTR real_3000
		mulsd	xmm0, QWORD PTR real_100
		movsd	QWORD PTR _p_1[ebp], xmm0
	
		prints OFFSET __Train_STPE
		printi DWORD PTR _i_7[ebp]
		prints OFFSET __Train_RATE
		movsd	xmm0, QWORD PTR _p_1[ebp]
		call dtoa
		prints eax
		println
	_Label121@Train:
	;当成功率达到95%时停止
	;if (p > 95) break;
		movsd	xmm0, QWORD PTR _p_1[ebp]
		comisd	xmm0, QWORD PTR real_95
		jbe	SHORT _Label13@Train
		jmp	SHORT _Label3@Train
	_Label13@Train:
		jmp	_Label2@Train
	_Label3@Train:
	mov	esp, ebp
	pop	ebp
	ret	0
_Train	ENDP
_TEXT	ENDS
;------------------------------------------------------------;
;							程序过程							；
;------------------------------------------------------------;
;初始化
_TEXT	SEGMENT
_j_1 = -20
_i_2 = -16
_k_3 = -12
_j_4 = -8
_i_5 = -4
_Init	PROC	
	push	ebp
	mov	ebp, esp
	sub	esp, 20
	;读文件
	mov edx,DWORD PTR _labels
    mov ecx,OFFSET train_labels
    call read_mnist_labels
	
    mov edx,DWORD PTR _images
    mov ecx,OFFSET train_images
    call read_mnist_images
	;初始化卷积核
;REP(i, filterNum)
	mov	DWORD PTR _i_5[ebp], 0
	jmp	SHORT _Label4@Init
_Label2@Init:
	mov	eax, DWORD PTR _i_5[ebp]
	add	eax, 1
	mov	DWORD PTR _i_5[ebp], eax
_Label4@Init:
	cmp	DWORD PTR _i_5[ebp], 5
	jae	SHORT _Label3@Init
	;REP(j, 5)REP(k, 5)
		mov	DWORD PTR _j_4[ebp], 0
		jmp	SHORT _Label7@Init
	_Label5@Init:
		mov	ecx, DWORD PTR _j_4[ebp]
		add	ecx, 1
		mov	DWORD PTR _j_4[ebp], ecx
	_Label7@Init:
		cmp	DWORD PTR _j_4[ebp], 5
		jae	SHORT _Label6@Init
		mov	DWORD PTR _k_3[ebp], 0
		jmp	SHORT _Label10@Init
			_Label8@Init:
				mov	edx, DWORD PTR _k_3[ebp]
				add	edx, 1
				mov	DWORD PTR _k_3[ebp], edx
			_Label10@Init:
				cmp	DWORD PTR _k_3[ebp], 5
				jae	SHORT _Label9@Init
			;CNN.filter[i].w[j][k] = 0.01 * (100 - Rand(200));
				push	200					; 000000c8H
				call	_Rand
				add	esp, 4
				mov	ecx, 100				; 00000064H
				sub	ecx, eax
				cvtsi2sd xmm0, ecx
				mulsd	xmm0, QWORD PTR real_0_01
				imul	edx, DWORD PTR _i_5[ebp], 200
				imul	eax, DWORD PTR _j_4[ebp], 40
				lea	ecx, DWORD PTR _CNN[edx+eax+15040]
				mov	edx, DWORD PTR _k_3[ebp]
				movsd	QWORD PTR [ecx+edx*8], xmm0
	
			jmp	SHORT _Label8@Init
	_Label9@Init:
		jmp	SHORT _Label5@Init
	_Label6@Init:
	jmp	SHORT _Label2@Init
_Label3@Init:
;REP(i, 10) REP(j, 14 * 14 * filterNum + 20)
		mov	DWORD PTR _i_2[ebp], 0
		jmp	SHORT _Label13@Init
	_Label11@Init:
		mov	eax, DWORD PTR _i_2[ebp]
		add	eax, 1
		mov	DWORD PTR _i_2[ebp], eax
	_Label13@Init:
		cmp	DWORD PTR _i_2[ebp], 10			; 0000000aH
		jae	SHORT _Label12@Init
		mov	DWORD PTR _j_1[ebp], 0
		jmp	SHORT _Label16@Init
		_Label14@Init:
			mov	ecx, DWORD PTR _j_1[ebp]
			add	ecx, 1
			mov	DWORD PTR _j_1[ebp], ecx
		_Label16@Init:
			cmp	DWORD PTR _j_1[ebp], 1000		; 000003e8H
			jae	SHORT _Label15@Init
		;CNN.w[i][j] = 0.01 * (100 - Rand(200));
			push	200					; 000000c8H
			call	_Rand
			add	esp, 4
			mov	edx, 100				; 00000064H
			sub	edx, eax
			cvtsi2sd xmm0, edx
			mulsd	xmm0, QWORD PTR real_0_01
			imul	eax, DWORD PTR _i_2[ebp], 8000
			mov	ecx, DWORD PTR _j_1[ebp]
			movsd	QWORD PTR _CNN[eax+ecx*8+24040], xmm0
		jmp	SHORT _Label14@Init
	_Label15@Init:
		jmp	SHORT _Label11@Init
	_Label12@Init:
	mov	esp, ebp
	pop	ebp
	ret	0
_Init	ENDP
;显示图像
.data
	align 4
	_ShowImage_Pix DB '@', 00H
	_ShowImage_Box DB ' ', 00H
	_hex	DB	' ..~~::!!**==&&@', 00H
.code
_TEXT	SEGMENT
_r_1 = -8						; size = 4
_c_2 = -4						; size = 4
_img_ = 8						; size = 4
_ShowImage PROC						;  
;void ShowImage(byte* img);
	push	ebp
	mov	ebp, esp
	sub	esp, 8
;putchar('\n');
	push	10					; 0000000aH
	call	 putchar
	add	esp, 4
	;REP(c, n_cols)
		mov	DWORD PTR _c_2[ebp], 0
		jmp	SHORT _Label4@ShowImage
	_Label2@ShowImage:
		mov	eax, DWORD PTR _c_2[ebp]
		add	eax, 1
		mov	DWORD PTR _c_2[ebp], eax
	_Label4@ShowImage:
		mov	ecx, DWORD PTR _c_2[ebp]
		cmp	ecx, DWORD PTR _n_cols
		jae	SHORT _Label1@ShowImage
	;REP(r, n_rows)
		mov	DWORD PTR _r_1[ebp], 0
		jmp	SHORT _Label7@ShowImage
	_Label5@ShowImage:
		mov	edx, DWORD PTR _r_1[ebp]
		add	edx, 1
		mov	DWORD PTR _r_1[ebp], edx
	_Label7@ShowImage:
		mov	eax, DWORD PTR _r_1[ebp]
		cmp	eax, DWORD PTR _n_rows
		jae	SHORT _Label6@ShowImage
		;putchar(hex[img[c * n_rows + r] >> 4]);
			mov	ecx, DWORD PTR _c_2[ebp]
			imul	ecx, DWORD PTR _n_rows
			add	ecx, DWORD PTR _r_1[ebp]
			mov	edx, DWORD PTR _img_[ebp]
			movzx	eax, BYTE PTR [edx+ecx]
			sar	eax, 4
			movsx	ecx, BYTE PTR _hex[eax]
			push	ecx
			call	 putchar
			add	esp, 4
		;putchar(hex[img[c * n_rows + r] & 0xf]);
		
			mov	edx, DWORD PTR _c_2[ebp]
			imul	edx, DWORD PTR _n_rows
			add	edx, DWORD PTR _r_1[ebp]
			mov	eax, DWORD PTR _img_[ebp]
			movzx	ecx, BYTE PTR [eax+edx]
			and	ecx, 15					; 0000000fH
			movsx	edx, BYTE PTR _hex[ecx]
			push	edx
			call	 putchar
			add	esp, 4
		jmp	SHORT _Label5@ShowImage
	_Label6@ShowImage:
	;putchar('\n');
		push	10					; 0000000aH
		call	 putchar
		add	esp, 4
	jmp	_Label2@ShowImage
_Label1@ShowImage:

	mov	esp, ebp
	pop	ebp
	ret	0
_ShowImage ENDP
_TEXT	ENDS
.data
    align 4
    __Test_start_string db "Start to test."
    __Test_calculated_string db "  Calculated: "
.code
;
;测试
_TEXT	SEGMENT
_max_1 = -28						; size = 8
tv67 = -20						; size = 4
_ans_2 = -16						; size = 4
_cmd_3 = -12						; size = 4
_i_ = -8						; size = 4
_k_4 = -4						; size = 4
_Test	PROC						;  
	push	ebp
	mov	ebp, esp
	sub	esp, 28					; 0000001cH
	prints offset __Test_start_string
	println
;int i = 10;
	mov	DWORD PTR _i_[ebp], 30			; 0000000aH
_Label2@Test:
;while (i--) 
	mov	eax, DWORD PTR _i_[ebp]
	mov	DWORD PTR tv67[ebp], eax
	mov	ecx, DWORD PTR _i_[ebp]
	sub	ecx, 1
	mov	DWORD PTR _i_[ebp], ecx
	cmp	DWORD PTR tv67[ebp], 0
	je	_Label3@Test
;int cmd = Rand(image_number);
		mov	edx, DWORD PTR _image_number
		push	edx
		call	_Rand
		add	esp, 4
		mov	DWORD PTR _cmd_3[ebp], eax
	;ShowImage(IMG(cmd));
		mov	eax, DWORD PTR _cmd_3[ebp]
		imul	eax, DWORD PTR _n_rows
		imul	eax, DWORD PTR _n_cols
		add	eax, DWORD PTR _images
		push	eax
		call	_ShowImage
		add	esp, 4
	;ForwardPropagation(cmd);
		mov	ecx, DWORD PTR _cmd_3[ebp]
		push	ecx
		call	_ForwardPropagation
		add	esp, 4
	;int ans = 0;
		mov	DWORD PTR _ans_2[ebp], 0
	;double max = -1e9;
		movsd	xmm0, QWORD PTR real__1E9
		movsd	QWORD PTR _max_1[ebp], xmm0
	;REP(k, 10)
		mov	DWORD PTR _k_4[ebp], 0
		jmp	SHORT _Label6@Test
	_Label4@Test:
		mov	edx, DWORD PTR _k_4[ebp]
		add	edx, 1
		mov	DWORD PTR _k_4[ebp], edx
	_Label6@Test:
		cmp	DWORD PTR _k_4[ebp], 10			; 0000000aH
		jae	SHORT _Label5@Test
	;if (max < CNN.out[k])
			mov	eax, DWORD PTR _k_4[ebp]
			movsd	xmm0, QWORD PTR _CNN[eax*8+104040]
			comisd	xmm0, QWORD PTR _max_1[ebp]
			jbe	SHORT _Label7@Test
			;ans = k;
				mov	ecx, DWORD PTR _k_4[ebp]
				mov	DWORD PTR _ans_2[ebp], ecx
			;max = CNN.out[k];
				mov	edx, DWORD PTR _k_4[ebp]
				movsd	xmm0, QWORD PTR _CNN[edx*8+104040]
				movsd	QWORD PTR _max_1[ebp], xmm0
				_Label7@Test:
		jmp	SHORT _Label4@Test
	_Label5@Test:
	;print("Calculated: ");
		prints offset __Test_calculated_string
		printi _ans_2[ebp]
		println
	jmp	_Label2@Test
_Label3@Test:
	mov	esp, ebp
	pop	ebp
	ret	0
_Test	ENDP
_TEXT	ENDS
.data
    align 4
.code
main PROC
    push edi
    push esi

	init_sys_env

	call _Init

	call _Train

	call _Test

    xor eax,eax
    pop esi
    pop edi
    ret
main ENDP

END main
