const c = @cImport({
    @cInclude("spawn.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/sysinfo.h");
    @cInclude("sys/types.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});

const std = @import("std");

const lua = @import("./lua.zig");
const LuaState = lua.LuaState;
const luaL_Reg = lua.luaL_Reg;

pub export fn env_operating_system(L: *LuaState) callconv(.C) c_int {
    L.checkStack(1);
    L.pushString("linux");

    return 1;
}

pub export fn env_create_directory(L: *LuaState) callconv(.C) c_int {
    const path = L.getString(1);

    _ = c.mkdir(path.ptr, 0o755);  // TODO

    return 0;
}

pub export fn env_file_exists(L: *LuaState) callconv(.C) c_int {
    L.checkStack(1);

    const path = L.getString(1);

    const result = c.access(path.ptr, c.F_OK); // TODO
    if (result != 0) {
        L.pushBoolean(false);
    } else {
        L.pushBoolean(true);
    }

    return 1;
}

pub export fn env_join_path(L: *LuaState) callconv(.C) c_int {
    const count = L.getStackTop();
    if (count == 0) {
        L.pushString("");
        return 1;
    }

    L.checkStack(2 * count - 1);
    for (0..count) |i| {
        if (i != 0) {
            L.pushString("/");
        }
        L.copy(1 + i);
    }

    L._concat(@intCast(2 * count - 1));

    return 1;
}

pub export fn env_processor_count(L: *LuaState) callconv(.C) c_int {
    L.pushNumber(c_int, c.get_nprocs());

    return 1;
}

const CBuffer = struct {
    buffer: [4096]u8,
    pos: usize,

    pub fn init() CBuffer {
        // TODO: take `size` as a parameter
        return .{
            .buffer = [_]u8{0} ** 4096,
            .pos = 0,
        };
    }

    pub fn write(self: *CBuffer, s: []const u8) [*c]u8 {
        if (self.pos + s.len + 1 > self.buffer.len) {
            unreachable;  // TODO
        }
        var p = &self.buffer[self.pos];
        @memcpy(self.buffer[self.pos..self.pos + s.len], s);
        self.pos += s.len + 1;
        
        return p;
    }
};

pub export fn env_spawn_background_process(L: *LuaState) callconv(.C) c_int {
    var buffer = CBuffer.init();

    var command_line = L.getString(1);

    var process_id: c_int = undefined;
    var argv = [_][*c]u8 { buffer.write("sh"), buffer.write("-c"), buffer.write(command_line), @ptrFromInt(0) };
    var envp = [_][*c]u8 { @ptrFromInt(0) };

    const result = c.posix_spawn(&process_id, "/bin/sh", null, null, &argv, &envp);

    if (result != 0) {
        unreachable;  // TODO
    }

    L.checkStack(1);
    L.pushLightUserData(@ptrFromInt(@as(usize, @intCast(process_id))));
    return 1;
}

pub export fn env_wait_for_background_process(L: *LuaState) callconv(.C) c_int {
    var wait_status: c_int = undefined;
    const process_id = c.wait(&wait_status);

    L.checkStack(2);
    L.pushLightUserData(@ptrFromInt(@as(usize, @intCast(process_id))));
    L.pushBoolean(c.WIFEXITED(wait_status) and c.WEXITSTATUS(wait_status) == 0);

    return 2;
}

pub const env = [_:luaL_Reg.SENTINEL]luaL_Reg{
    luaL_Reg{
        .name = "operating_system",
        .func = &env_operating_system,
    },
    luaL_Reg{
        .name = "create_directory",
        .func = &env_create_directory,
    },
    luaL_Reg{
        .name = "file_exists",
        .func = &env_file_exists,
    },
    luaL_Reg{
        .name = "join_path",
        .func = &env_join_path,
    },
    luaL_Reg{
        .name = "processor_count",
        .func = &env_processor_count,
    },
    luaL_Reg{
        .name = "spawn_background_process",
        .func = &env_spawn_background_process,
    },
    luaL_Reg{
        .name = "wait_for_background_process",
        .func = &env_wait_for_background_process,
    },
};

pub export fn luaopen_env(L: *LuaState) c_int {
    L.checkStack(1);

    L._createtable(0, env.len);
    L._L_setfuncs(&env, 0);
    return 1;
}
