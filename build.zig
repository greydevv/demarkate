const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const demarkate_lib = b.addModule("demarkate", .{
        .root_source_file = b.path("src/demarkate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shim_lib = b.createModule(.{
        .root_source_file = b.path("src/shim/impl.zig"),
        .target = target,
        .optimize = optimize
    });

    shim_lib.addImport("demarkate", demarkate_lib);

    const emit_wasm_exe = b.option(bool, "emit-wasm", "emit wasm32-freestanding executable") orelse false;
    // Build wasm exe
    if (emit_wasm_exe) {
        const wasm_mod = b.createModule(.{
            .root_source_file = b.path("src/shim/wasm.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize
        });

        wasm_mod.addImport("demarkate", demarkate_lib);

        const wasm_exe = b.addExecutable(.{
            .name = "demarkate",
            .root_module = wasm_mod
        });

        wasm_exe.rdynamic = true;
        wasm_exe.export_table = true;
        wasm_exe.entry = .disabled;
        wasm_exe.export_memory = true;

        b.installArtifact(wasm_exe);
    }

    // Running exe
    {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("bin/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("demarkate", demarkate_lib);

        const exe = b.addExecutable(.{
            .name = "text-to-html",
            .root_module = exe_mod,
        });

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Testing demarkate & shim implementation
    {
        const lib_unit_tests = b.addTest(.{
            .root_module = demarkate_lib,
            .name = "lib"
        });

        const shim_unit_tests = b.addTest(.{
            .root_module = shim_lib,
            .name = "shim"
        });

        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        const run_shim_unit_tests = b.addRunArtifact(shim_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
        test_step.dependOn(&run_shim_unit_tests.step);
    }
}
