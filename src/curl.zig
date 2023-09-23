const c = @cImport({
    @cInclude("curl/curl.h");
});

const std = @import("std");

const lua = @import("./lua.zig");
const LuaState = lua.LuaState;
const luaL_Reg = lua.luaL_Reg;

pub export fn curl_write_function(ptr: [*]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.C) usize {
    const len = size * nmemb;
    var buffer: *std.ArrayList(u8) = @alignCast(@ptrCast(userdata));

    buffer.appendSlice(ptr[0..len]) catch return c.CURL_WRITEFUNC_ERROR;
    return len;
}

const HttpClient = struct {
    client: *c.CURL,

    const Error = error.HttpClientError;

    pub fn init() !HttpClient {
        if (c.curl_easy_init()) |client| {
            return .{
                .client = client,
            };
        } else {
            return HttpClient.Error;
        }
    }

    pub fn deinit(self: *HttpClient) void {
        c.curl_easy_cleanup(self.client);
    }

    pub fn setUrl(self: *HttpClient, url: []const u8) !void {
        const result = c.curl_easy_setopt(self.client, c.CURLOPT_URL, url.ptr);
        if (result != c.CURLE_OK) {
            return HttpClient.Error;
        }
    }

    pub fn setPostData(self: *HttpClient, data: []const u8) void {
        _ = c.curl_easy_setopt(self.client, c.CURLOPT_POSTFIELDS, data.ptr);
        _ = c.curl_easy_setopt(self.client, c.CURLOPT_POSTFIELDSIZE_LARGE, data.len);
    }

    pub fn perform(self: *HttpClient, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        _ = c.curl_easy_setopt(self.client, c.CURLOPT_WRITEDATA, &buffer);
        _ = c.curl_easy_setopt(self.client, c.CURLOPT_WRITEFUNCTION, &curl_write_function);

        const result = c.curl_easy_perform(self.client);
        if (result != c.CURLE_OK) {
            return HttpClient.Error;
        }

        if (buffer.toOwnedSlice()) |response| {
            return response;
        } else |_| {
            return HttpClient.Error;
        }
    }
};

fn _curl_get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = try HttpClient.init();
    defer client.deinit();

    try client.setUrl(url);
    return try client.perform(allocator);
}

pub export fn curl_get(L: *LuaState) callconv(.C) c_int {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    const url = L.getString(1);

    if (_curl_get(allocator, url)) |response| {
        defer allocator.free(response);
        L.checkStack(1);
        L.pushString(response);
        return 1;
    } else |_| {
        L.checkStack(1);
        L.pushNil();
        return 1;
    }
}

fn _curl_post(allocator: std.mem.Allocator, url: []const u8, data: []const u8) ![]u8 {
    var client = try HttpClient.init();
    defer client.deinit();

    try client.setUrl(url);
    client.setPostData(data);
    return try client.perform(allocator);
}

pub export fn curl_post(L: *LuaState) callconv(.C) c_int {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    const url = L.getString(1);
    const data = L.getString(2);

    if (_curl_post(allocator, url, data)) |response| {
        defer allocator.free(response);
        L.checkStack(1);
        L.pushString(response);
        return 1;
    } else |_| {
        L.checkStack(1);
        L.pushNil();
        return 1;
    }
}

pub const curl = [_:luaL_Reg.SENTINEL]luaL_Reg{
    luaL_Reg{
        .name = "get",
        .func = &curl_get,
    },
    luaL_Reg{
        .name = "post",
        .func = &curl_post,
    },
};

pub export fn luaopen_curl(L: *LuaState) c_int {
    L.checkStack(1);

    L._createtable(0, curl.len);
    L._L_setfuncs(&curl, 0);
    return 1;
}
