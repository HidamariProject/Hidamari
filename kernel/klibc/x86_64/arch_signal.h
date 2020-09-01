enum { REG_R8 = 0 };
#define REG_R8 REG_R8
enum { REG_R9 = 1 };
#define REG_R9 REG_R9
enum { REG_R10 = 2 };
#define REG_R10 REG_R10
enum { REG_R11 = 3 };
#define REG_R11 REG_R11
enum { REG_R12 = 4 };
#define REG_R12 REG_R12
enum { REG_R13 = 5 };
#define REG_R13 REG_R13
enum { REG_R14 = 6 };
#define REG_R14 REG_R14
enum { REG_R15 = 7 };
#define REG_R15 REG_R15
enum { REG_RDI = 8 };
#define REG_RDI REG_RDI
enum { REG_RSI = 9 };
#define REG_RSI REG_RSI
enum { REG_RBP = 10 };
#define REG_RBP REG_RBP
enum { REG_RBX = 11 };
#define REG_RBX REG_RBX
enum { REG_RDX = 12 };
#define REG_RDX REG_RDX
enum { REG_RAX = 13 };
#define REG_RAX REG_RAX
enum { REG_RCX = 14 };
#define REG_RCX REG_RCX
enum { REG_RSP = 15 };
#define REG_RSP REG_RSP
enum { REG_RIP = 16 };
#define REG_RIP REG_RIP
enum { REG_EFL = 17 };
#define REG_EFL REG_EFL
enum { REG_CSGSFS = 18 };
#define REG_CSGSFS REG_CSGSFS
enum { REG_ERR = 19 };
#define REG_ERR REG_ERR
enum { REG_TRAPNO = 20 };
#define REG_TRAPNO REG_TRAPNO
enum { REG_OLDMASK = 21 };
#define REG_OLDMASK REG_OLDMASK
enum { REG_CR2 = 22 };
#define REG_CR2 REG_CR2

typedef uint64_t greg_t, gregset_t[23];
typedef struct _fpstate {
	uint16_t cwd, swd, ftw, fop;
	uint64_t rip, rdp;
	uint32_t mxcsr, mxcr_mask;
	struct {
		uint16_t significand[4], exponent, padding[3];
	} _st[8];
	struct {
		uint32_t element[4];
	} _xmm[16];
	uint32_t padding[24];
} *fpregset_t;

struct sigcontext {
	uint64_t r8, r9, r10, r11, r12, r13, r14, r15;
	uint64_t rdi, rsi, rbp, rbx, rdx, rax, rcx, rsp, rip, eflags;
	uint16_t cs, gs, fs, __pad0;
	uint64_t err, trapno, oldmask, cr2;
	struct _fpstate *fpstate;
	uint64_t __reserved1[8];
};

typedef struct {
	gregset_t gregs;
	fpregset_t fpregs;
	uint64_t __reserved1[8];
} mcontext_t;

typedef struct sigaltstack {
	void *ss_sp;
	int ss_flags;
	size_t ss_size;
} stack_t;

typedef struct __ucontext {
	uint64_t uc_flags;
	struct __ucontext *uc_link;
	stack_t uc_stack;
	mcontext_t uc_mcontext;
	size_t uc_sigmask;
	uint64_t __fpregs_mem[64];
} ucontext_t;

