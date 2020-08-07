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
        miniz.setBuildMode(mode);

        const exe = b.addExecutable(kernelBinary, "kernel/main.zig");
        exe.addIncludeDir("kernel");
        exe.addIncludeDir("kernel/klibc");
        exe.setTarget(kernelTarget);
        exe.setBuildMode(mode);
        exe.setOutputDir(kernelOutputDir);
        exe.linkLibrary(wasm3);
        exe.linkLibrary(ckern);
        exe.linkLibrary(miniz);
        exe.strip = true;

        kernel_step.dependOn(&exe.step);
    }

    const apps_step = b.step("apps", "Build Userspace Apps"); {
        const app = b.addExecutable("init", "apps/init/main.zig");
        app.setTarget(wasiTarget);
        app.setBuildMode(mode);
        app.setOutputDir(tempOutputDir);

        apps_step.dependOn(&app.step);
        apps_step.dependOn(&b.addSystemCommand(&[_][]const u8{"cp", app.getOutputPath(), rootfsOutputDir ++ "/bin/init"}).step);
    }

    //const run_cmd = exe.run();
    //run_cmd.step.dependOn(b.getInstallStep());

    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);
    b.default_step.dependOn(apps_step);
    b.default_step.dependOn(kernel_step);
}
