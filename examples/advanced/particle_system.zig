const std = @import("std");
const mfs = @import("mfs");
const zmath = @import("zmath");
const math = @import("../../src/math/math.zig");

// A complete particle system example using MFS Engine
// This demonstrates:
// - Dynamic particle creation and management
// - GPU instancing for efficient rendering
// - Time-based animation and simulation
// - Scene integration with camera controls

/// Particle data structure
const Particle = struct {
    position: math.Vec3,
    velocity: math.Vec3,
    color: math.Vec4,
    size: f32,
    life: f32,
    max_life: f32,

    pub fn init(position: math.Vec3, velocity: math.Vec3, color: math.Vec4, size: f32, life: f32) Particle {
        return .{
            .position = position,
            .velocity = velocity,
            .color = color,
            .size = size,
            .life = life,
            .max_life = life,
        };
    }

    pub fn update(self: *Particle, delta_time: f32) void {
        self.life -= delta_time;
        self.position = self.position.add(self.velocity.scale(delta_time));
        self.velocity = self.velocity.add(math.Vec3.new(0.0, -9.8 * delta_time, 0.0)); // Apply gravity
        
        // Fade out based on remaining life
        self.color.a = self.life / self.max_life;
    }

    pub fn isAlive(self: Particle) bool {
        return self.life > 0.0;
    }
};

/// Particle emitter that creates and manages particles
const ParticleEmitter = struct {
    particles: std.ArrayList(Particle),
    emit_timer: f32,
    emit_rate: f32,
    position: math.Vec3,
    direction: math.Vec3,
    spread: f32,
    particle_life: f32,
    particle_speed: f32,
    particle_size: f32,
    particle_color: math.Vec4,
    is_active: bool,

    pub fn init(allocator: std.mem.Allocator, max_particles: usize) !ParticleEmitter {
        return ParticleEmitter{
            .particles = try std.ArrayList(Particle).initCapacity(allocator, max_particles),
            .emit_timer = 0.0,
            .emit_rate = 0.05, // Time between particle emissions
            .position = math.Vec3.zero(),
            .direction = math.Vec3.new(0.0, 1.0, 0.0),
            .spread = 0.3,
            .particle_life = 2.5,
            .particle_speed = 5.0,
            .particle_size = 0.2,
            .particle_color = math.Vec4.new(1.0, 0.5, 0.0, 1.0), // Orange
            .is_active = true,
        };
    }

    pub fn deinit(self: *ParticleEmitter) void {
        self.particles.deinit();
    }

    pub fn update(self: *ParticleEmitter, delta_time: f32) void {
        // Update existing particles
        var i: usize = 0;
        while (i < self.particles.items.len) {
            var particle = &self.particles.items[i];
            particle.update(delta_time);
            
            if (!particle.isAlive()) {
                // Remove dead particles by swapping with the last element
                _ = self.particles.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Emit new particles
        if (self.is_active) {
            self.emit_timer -= delta_time;
            if (self.emit_timer <= 0.0) {
                self.emit_timer = self.emit_rate;
                self.emitParticle() catch {};
            }
        }
    }

    pub fn emitParticle(self: *ParticleEmitter) !void {
        if (self.particles.items.len >= self.particles.capacity) {
            return; // Reached max particles
        }

        const random = std.crypto.random;

        // Generate random direction within spread cone
        const angle1 = random.float(f32) * std.math.tau;
        const angle2 = random.float(f32) * self.spread;
        
        const x = @sin(angle2) * @cos(angle1);
        const y = @cos(angle2);
        const z = @sin(angle2) * @sin(angle1);
        
        var direction = self.direction;
        if (direction.length() < 0.001) {
            direction = math.Vec3.new(0.0, 1.0, 0.0);
        }
        
        // Create quaternion from up vector to direction
        const up = math.Vec3.new(0.0, 1.0, 0.0);
        const rotation = math.Quat.fromTwoVectors(up, direction.normalize());
        const random_dir = rotation.rotate(math.Vec3.new(x, y, z));
        
        // Create particle with random variations
        const speed_var = self.particle_speed * (0.8 + random.float(f32) * 0.4);
        const size_var = self.particle_size * (0.8 + random.float(f32) * 0.4);
        const life_var = self.particle_life * (0.8 + random.float(f32) * 0.4);
        
        const color_var = math.Vec4.new(
            self.particle_color.x * (0.9 + random.float(f32) * 0.2),
            self.particle_color.y * (0.9 + random.float(f32) * 0.2),
            self.particle_color.z * (0.9 + random.float(f32) * 0.2),
            self.particle_color.w
        );
        
        const velocity = random_dir.scale(speed_var);
        
        try self.particles.append(Particle.init(
            self.position,
            velocity,
            color_var,
            size_var, 
            life_var
        ));
    }

    pub fn setPosition(self: *ParticleEmitter, position: math.Vec3) void {
        self.position = position;
    }

    pub fn setDirection(self: *ParticleEmitter, direction: math.Vec3) void {
        self.direction = direction;
    }

    pub fn setParticleProperties(
        self: *ParticleEmitter, 
        color: math.Vec4, 
        size: f32, 
        life: f32, 
        speed: f32
    ) void {
        self.particle_color = color;
        self.particle_size = size;
        self.particle_life = life;
        self.particle_speed = speed;
    }

    pub fn setEmissionRate(self: *ParticleEmitter, particles_per_second: f32) void {
        self.emit_rate = 1.0 / particles_per_second;
    }

    pub fn burst(self: *ParticleEmitter, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try self.emitParticle();
        }
    }
};

/// Instance data for GPU instanced rendering
const ParticleInstance = struct {
    position: [4]f32, // xyz + size
    color: [4]f32,
};

/// Main application state
const ParticleSystemDemo = struct {
    engine: *mfs.Engine,
    allocator: std.mem.Allocator,
    camera: mfs.Camera,
    particle_emitters: std.ArrayList(ParticleEmitter),
    particle_mesh: mfs.MeshHandle,
    particle_material: mfs.MaterialHandle,
    instance_buffer: mfs.BufferHandle,
    max_instances: u32,
    time: f32,
    camera_orbit: f32,

    pub fn init(allocator: std.mem.Allocator) !*ParticleSystemDemo {
        // Initialize the engine
        var engine = try mfs.Engine.init(.{
            .allocator = allocator,
            .window_title = "MFS Particle System Demo",
            .window_width = 1280,
            .window_height = 720,
            .msaa_samples = 4,
        });

        const self = try allocator.create(ParticleSystemDemo);
        errdefer allocator.destroy(self);

        self.* = .{
            .engine = engine,
            .allocator = allocator,
            .camera = try mfs.Camera.init(.perspective),
            .particle_emitters = std.ArrayList(ParticleEmitter).init(allocator),
            .particle_mesh = undefined,
            .particle_material = undefined,
            .instance_buffer = undefined,
            .max_instances = 10000,
            .time = 0.0,
            .camera_orbit = 0.0,
        };

        try self.initResources();
        try self.setupScene();

        return self;
    }

    pub fn deinit(self: *ParticleSystemDemo) void {
        self.destroyResources();
        
        for (self.particle_emitters.items) |*emitter| {
            emitter.deinit();
        }
        self.particle_emitters.deinit();
        
        self.engine.deinit();
        self.allocator.destroy(self);
    }

    fn initResources(self: *ParticleSystemDemo) !void {
        // Create particle quad mesh (billboarded)
        self.particle_mesh = try self.engine.createBillboardQuad();

        // Create instance buffer for GPU instancing
        self.instance_buffer = try self.engine.createBuffer(.{
            .size = self.max_instances * @sizeOf(ParticleInstance),
            .usage = .{ .vertex = true, .dynamic = true },
        });

        // Load the particle shader
        const shader = try self.engine.createShader(.{
            .vertex = @embedFile("shaders/particle.vert"),
            .fragment = @embedFile("shaders/particle.frag"),
        });

        // Create particle texture
        const particle_texture = try self.engine.createTextureFromFile("textures/particle.png");

        // Create particle material with additive blending
        self.particle_material = try self.engine.createMaterial(.{
            .shader = shader,
            .textures = &[_]mfs.TextureBinding{
                .{ .binding = 0, .texture = particle_texture },
            },
            .blend_mode = .additive,
            .depth_write = false,
        });

        // Set up camera
        self.camera.setPosition(math.Vec3.new(0.0, 5.0, 15.0));
        self.camera.lookAt(math.Vec3.zero());
    }

    fn destroyResources(self: *ParticleSystemDemo) void {
        self.engine.destroyMesh(self.particle_mesh);
        self.engine.destroyMaterial(self.particle_material);
        self.engine.destroyBuffer(self.instance_buffer);
    }

    fn setupScene(self: *ParticleSystemDemo) !void {
        // Create a fire emitter
        var fire_emitter = try ParticleEmitter.init(self.allocator, 1000);
        fire_emitter.setPosition(math.Vec3.new(0.0, 0.0, 0.0));
        fire_emitter.setDirection(math.Vec3.new(0.0, 1.0, 0.0));
        fire_emitter.setParticleProperties(
            math.Vec4.new(1.0, 0.5, 0.0, 1.0), // Orange
            0.5,  // Size
            1.5,  // Life
            3.0   // Speed
        );
        fire_emitter.setEmissionRate(40.0);
        try fire_emitter.burst(50);
        try self.particle_emitters.append(fire_emitter);

        // Create a smoke emitter
        var smoke_emitter = try ParticleEmitter.init(self.allocator, 500);
        smoke_emitter.setPosition(math.Vec3.new(0.0, 0.8, 0.0));
        smoke_emitter.setDirection(math.Vec3.new(0.0, 1.0, 0.0));
        smoke_emitter.setParticleProperties(
            math.Vec4.new(0.6, 0.6, 0.6, 0.3), // Gray
            1.0,  // Size
            3.0,  // Life
            1.5   // Speed
        );
        smoke_emitter.setEmissionRate(20.0);
        try self.particle_emitters.append(smoke_emitter);

        // Create a fountain emitter
        var fountain_emitter = try ParticleEmitter.init(self.allocator, 1000);
        fountain_emitter.setPosition(math.Vec3.new(-5.0, 0.0, -5.0));
        fountain_emitter.setDirection(math.Vec3.new(0.0, 1.0, 0.0));
        fountain_emitter.setParticleProperties(
            math.Vec4.new(0.2, 0.4, 1.0, 1.0), // Blue
            0.3,  // Size
            4.0,  // Life
            8.0   // Speed
        );
        fountain_emitter.setEmissionRate(60.0);
        try self.particle_emitters.append(fountain_emitter);

        // Create an explosion emitter (non-continuous)
        var explosion_emitter = try ParticleEmitter.init(self.allocator, 500);
        explosion_emitter.setPosition(math.Vec3.new(5.0, 0.0, 5.0));
        explosion_emitter.setDirection(math.Vec3.new(0.0, 0.0, 0.0));
        explosion_emitter.spread = std.math.pi; // Full sphere emission
        explosion_emitter.setParticleProperties(
            math.Vec4.new(1.0, 0.3, 0.0, 1.0), // Orange-red
            0.4,  // Size
            2.0,  // Life
            10.0  // Speed
        );
        explosion_emitter.is_active = false; // Only bursts
        try explosion_emitter.burst(200);
        try self.particle_emitters.append(explosion_emitter);
    }

    pub fn update(self: *ParticleSystemDemo, delta_time: f32) !void {
        self.time += delta_time;

        // Update camera orbit
        self.camera_orbit += delta_time * 0.2;
        const camera_x = @sin(self.camera_orbit) * 15.0;
        const camera_z = @cos(self.camera_orbit) * 15.0;
        self.camera.setPosition(math.Vec3.new(camera_x, 5.0, camera_z));
        self.camera.lookAt(math.Vec3.zero());

        // Update particle emitters
        for (self.particle_emitters.items) |*emitter| {
            emitter.update(delta_time);
        }

        // Trigger a new explosion every 5 seconds
        if (@mod(self.time, 5.0) < delta_time) {
            if (self.particle_emitters.items.len >= 4) {
                var explosion = &self.particle_emitters.items[3];
                try explosion.burst(200);
            }
        }

        // Handle input
        try self.handleInput();
    }

    fn handleInput(self: *ParticleSystemDemo) !void {
        const input = self.engine.input;

        // Close on escape
        if (input.isKeyPressed(.escape)) {
            self.engine.requestExit();
        }

        // Add new particles on mouse click
        if (input.isMouseButtonPressed(.left)) {
            // Create a ray from the camera through the mouse position
            const mouse_pos = input.getMousePosition();
            const ray = self.camera.screenPointToRay(mouse_pos.x, mouse_pos.y);
            
            // Create a temporary particle burst at the ray direction
            var burst_emitter = try ParticleEmitter.init(self.allocator, 100);
            defer burst_emitter.deinit();
            
            burst_emitter.setPosition(ray.origin.add(ray.direction.scale(5.0)));
            burst_emitter.setDirection(math.Vec3.new(0.0, 1.0, 0.0));
            burst_emitter.setParticleProperties(
                math.Vec4.new(0.0, 1.0, 0.5, 1.0), // Turquoise
                0.3,  // Size
                1.0,  // Life
                5.0   // Speed
            );
            burst_emitter.is_active = false;
            try burst_emitter.burst(50);
            
            try self.particle_emitters.append(burst_emitter);
        }
    }

    pub fn render(self: *ParticleSystemDemo) !void {
        const engine = self.engine;

        // Begin frame
        try engine.beginFrame();
        engine.clearScreen(.{ 0.05, 0.05, 0.1, 1.0 });

        // Update camera matrices
        self.camera.updateViewMatrix();
        try engine.setCamera(self.camera);

        // Draw ground grid
        try engine.drawGrid(20, 1.0, math.Vec4.new(0.3, 0.3, 0.3, 1.0));

        // Collect all particles into instance data
        var instance_count: u32 = 0;
        var instance_data = try self.allocator.alloc(ParticleInstance, self.max_instances);
        defer self.allocator.free(instance_data);

        for (self.particle_emitters.items) |emitter| {
            for (emitter.particles.items) |particle| {
                if (instance_count >= self.max_instances) break;
                
                instance_data[instance_count] = .{
                    .position = .{
                        particle.position.x,
                        particle.position.y,
                        particle.position.z,
                        particle.size,
                    },
                    .color = .{
                        particle.color.x,
                        particle.color.y,
                        particle.color.z,
                        particle.color.w,
                    },
                };
                instance_count += 1;
            }
        }

        // Upload instance data to GPU
        try engine.updateBuffer(self.instance_buffer, instance_data[0..instance_count]);

        // Draw particles using instancing
        engine.bindMaterial(self.particle_material);
        try engine.drawMeshInstanced(self.particle_mesh, self.instance_buffer, instance_count);

        // End frame
        try engine.endFrame();
    }

    pub fn run(self: *ParticleSystemDemo) !void {
        while (!self.engine.shouldClose()) {
            // Get delta time
            const delta_time = self.engine.getDeltaTime();
            
            // Update
            try self.update(delta_time);
            
            // Render
            try self.render();
            
            // Poll events
            try self.engine.pollEvents();
        }
    }
};

pub fn main() !void {
    // Set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create and run demo
    var demo = try ParticleSystemDemo.init(allocator);
    defer demo.deinit();

    try demo.run();
}