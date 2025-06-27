const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const demarkate = b.addModule("demarkate", .{
        .root_source_file = b.path("src/demarkate.zig"),
        .target = target,
        .optimize = optimize,
    });

    // (Optionally) building for wasm32-freestanding
    const compile_to_wasm = b.option(bool, "wasm", "target wasm32-freestanding") orelse false;
    {
        if (compile_to_wasm) {
            const wasm_shim_mod = b.createModule(.{
                .root_source_file = b.path("src/shim/wasm.zig"),
                .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
                .optimize = optimize
            });

            wasm_shim_mod.addImport("demarkate", demarkate);

            const wasm_exe = b.addExecutable(.{
                .name = "demarkate",
                .root_module = wasm_shim_mod
            });

            wasm_exe.rdynamic = true;
            wasm_exe.export_table = true;
            wasm_exe.entry = .disabled;
            wasm_exe.export_memory = true;
            b.installArtifact(wasm_exe);
            return;
        }
    }

    // Building lib
    {
        const lib = b.addLibrary(.{
            .linkage = .static,
            .name = "demarkate",
            .root_module = demarkate,
        });

        b.installArtifact(lib);
    }

    // Running exe
    {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("bin/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("demarkate", demarkate);

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

    // Testing lib
    {
        const lib_unit_tests = b.addTest(.{
            .root_module = demarkate
        });

        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
    }
}
