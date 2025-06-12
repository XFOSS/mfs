const common = @import("../common.zig");
const interface = @import("../interface.zig");

pub const d3d11 = @import("d3d11_backend.zig");
pub const d3d12 = @import("d3d12_backend.zig");

test {
    _ = d3d11;
    _ = d3d12;
}
