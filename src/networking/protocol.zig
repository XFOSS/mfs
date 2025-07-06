//! Network Protocol Implementation (Stub)

const std = @import("std");

pub const Message = struct {
    type: MessageType,
    sender_id: u32 = 0,
    timestamp: i64 = 0,
    data: []const u8 = "",

    pub fn getSize(self: *const Message) u64 {
        return @sizeOf(MessageType) + @sizeOf(u32) + @sizeOf(i64) + self.data.len;
    }
};

pub const MessageType = enum {
    player_join,
    player_leave,
    game_state,
    player_input,
    chat_message,
    ping,
    pong,
    unknown,
};

pub const MessageHandler = *const fn (message: Message) anyerror!void;
