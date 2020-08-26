const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const wasiTarget = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.wasm32,
        .os_tag = Target.Os.Tag.wasi,
    };

    // Soon we'll support other targets (riscv-uefi, et al.)

    const kernelTarget = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .cpu_model = .baseline,
        .os_tag = Target.Os.Tag.uefi,
        .abi = Target.Abi.msvc,
    };

    const kernelBinary: []const u8 = "bootx64";
    const kernelOutputDir: []const u8 = "output/efi/boot";
    const kernelClangTarget: []const u8 = "--target=x86_64-unknown-windows-msvc";

    const rootfsOutputDir: []const u8 = "output/rootfs";
    const tempOutputDir: []const u8 = "output/temp";

    const mode = b.standardReleaseOptions();

    const app_names = [_][]const u8{
        "init",
    };

    const apps_step = b.step("apps", "Build Userspace Apps"); {
        inline for (app_names) |app_name| {
            const app = b.addExecutable(app_name, "apps/" ++ app_name ++ "/main.zig");
            app.setTarget(wasiTarget);
            app.setBuildMode(mode);
            app.setOutputDir(tempOutputDir);
            apps_step.dependOn(&app.step);
        }
    }

    const rootfs_step = b.step("rootfs", "Build Root Filesystem"); {
        // hack to always generate fresh rootfs
        rootfs_step.dependOn(&b.addSystemCommand(&[_][]const u8{"rm", "-rf", rootfsOutputDir}).step);

        rootfs_step.dependOn(&b.addSystemCommand(&[_][]const u8{"rsync", "-a", "rootfs_skel/", rootfsOutputDir}).step);

        rootfs_step.dependOn(apps_step);
        inline for (app_names) |app_name| {
            rootfs_step.dependOn(&b.addSystemCommand(&[_][]const u8{"cp", tempOutputDir ++ "/" ++ app_name ++ ".wasm", rootfsOutputDir ++ "/bin/" ++ app_name}).step);
        }
    }

    const initrd_step = b.step("initrd", "Build Initial Ramdisk"); {
        initrd_step.dependOn(rootfs_step);

        // hack to always generate fresh initrd
        initrd_step.dependOn(&b.addSystemCommand(&[_][]const u8{"rm", "-f", tempOutputDir ++ "/initrd.zip"}).step);

        // another hack
        //initrd_step.dependOn(&b.addSystemCommand(&[_][]const u8{"zip", "-x", "*.keepdir*", "-x", "**/*.keepdir*", "-r", tempOutputDir ++ "/initrd.zip", "."}).step);
        // invoke 'sh' to use chdir
        initrd_step.dependOn(&b.addSystemCommand(&[_][]const u8{"sh", "-c", "cd '" ++ rootfsOutputDir ++ "' && zip -x '*.keepdir*' -x '**/*.keepdir*' -9r '../../" ++ tempOutputDir ++ "/initrd.zip' ."}).step);
    }

    const kernel_step = b.step("kernel", "Build Kernel"); {
        const wasm3 = b.addStaticLibrary("wasm3", null);
        wasm3.addIncludeDir("kernel");
        wasm3.addIncludeDir("kernel/klibc");
        wasm3.addIncludeDir("kernel/wasm3/source");
        wasm3.addCSourceFile("kernel/wasm3_all.c", &[_][]const u8{kernelClangTarget});
        wasm3.setTarget(CrossTarget{.cpu_arch = kernelTarget.cpu_arch, .cpu_model = .baseline});
        wasm3.setBuildMode(std.builtin.Mode.ReleaseSmall); // Needed because of undefined behavior. TODO FIXME.

        const ckern = b.addStaticLibrary("ckern", null);
        ckern.addIncludeDir("kernel");
        ckern.addIncludeDir("kernel/klibc");
        ckern.addCSourceFile("kernel/sanitytests.c", &[_][]const u8{kernelClangTarget});
        ckern.setTarget(CrossTarget{.cpu_arch = kernelTarget.cpu_arch, .cpu_model = .baseline});
        ckern.setBuildMode(mode);

        const miniz = b.addStaticLibrary("miniz", null);
        miniz.addIncludeDir("kernel");
        miniz.addIncludeDir("kernel/klibc");
        miniz.addIncludeDir("kernel/miniz");
        miniz.addCSourceFile("kernel/miniz/miniz.c", &[_][]const u8{kernelClangTarget});
        miniz.setTarget(CrossTarget{.cpu_arch = kernelTarget.cpu_arch, .cpu_model = .baseline});
        miniz.setBuildMode(std.builtin.Mode.ReleaseSmall); // Needed because of undefined behavior. TODO FIXME.

        const exe = b.addExecutable(kernelBinary, "kernel/main.zig");
        exe.addIncludeDir("kernel");
        exe.addIncludeDir("kernel/klibc");
        exe.setTarget(kernelTarget);
        exe.setBuildMode(mode);
        exe.setOutputDir(kernelOutputDir);
        exe.linkLibrary(wasm3);
        exe.linkLibrary(ckern);
        exe.linkLibrary(miniz);

        kernel_step.dependOn(&b.addSystemCommand(&[_][]const u8{"touch", "kernel/utsname_extra.h"}).step);
        kernel_step.dependOn(initrd_step);
        kernel_step.dependOn(&exe.step);
    }

    //const run_cmd = exe.run();
    //run_cmd.step.dependOn(b.getInstallStep());

    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);
    b.default_step.dependOn(kernel_step);
}
