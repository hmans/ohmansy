use anyhow::{Context, Result, bail};
use eframe::{egui_glow, glow};
use glam::Mat4;
use glow::HasContext;

use crate::capture::Card;

pub struct Renderer {
    program: glow::Program,
    vao: glow::VertexArray,
    textures: Vec<glow::Texture>,
    pub cards: Vec<Card>,
    pub device: String,
}

impl Renderer {
    pub fn new(gl: &glow::Context) -> Result<Self> {
        // SAFETY: eframe owns this current GL context. All GL operations happen
        // on its rendering thread, including uploads and teardown.
        unsafe {
            let version = egui_glow::ShaderVersion::get(gl);
            let program = gl.create_program().map_err(anyhow::Error::msg)?;
            for (kind, source) in [
                (glow::VERTEX_SHADER, include_str!("window.vert")),
                (glow::FRAGMENT_SHADER, include_str!("window.frag")),
            ] {
                let shader = gl.create_shader(kind).map_err(anyhow::Error::msg)?;
                gl.shader_source(
                    shader,
                    &format!("{}\n{source}", version.version_declaration()),
                );
                gl.compile_shader(shader);
                if !gl.get_shader_compile_status(shader) {
                    let error = gl.get_shader_info_log(shader);
                    gl.delete_shader(shader);
                    gl.delete_program(program);
                    bail!("Spatial shader failed: {error}");
                }
                gl.attach_shader(program, shader);
                gl.delete_shader(shader);
            }
            gl.link_program(program);
            if !gl.get_program_link_status(program) {
                let error = gl.get_program_info_log(program);
                gl.delete_program(program);
                bail!("Spatial shader link failed: {error}");
            }
            Ok(Self {
                program,
                vao: gl.create_vertex_array().map_err(anyhow::Error::msg)?,
                textures: vec![],
                cards: vec![],
                device: gl.get_parameter_string(glow::RENDERER),
            })
        }
    }

    pub fn replace(&mut self, gl: &glow::Context, cards: Vec<Card>) -> Result<()> {
        // SAFETY: called from eframe's update on the current GL context.
        unsafe {
            for texture in self.textures.drain(..) {
                gl.delete_texture(texture);
            }
            gl.pixel_store_i32(glow::UNPACK_ALIGNMENT, 1);
            for card in &cards {
                let texture = gl
                    .create_texture()
                    .map_err(anyhow::Error::msg)
                    .context("Create window texture")?;
                gl.bind_texture(glow::TEXTURE_2D, Some(texture));
                gl.tex_parameter_i32(
                    glow::TEXTURE_2D,
                    glow::TEXTURE_MIN_FILTER,
                    glow::LINEAR_MIPMAP_LINEAR as i32,
                );
                gl.tex_parameter_i32(
                    glow::TEXTURE_2D,
                    glow::TEXTURE_MAG_FILTER,
                    glow::LINEAR as i32,
                );
                for axis in [glow::TEXTURE_WRAP_S, glow::TEXTURE_WRAP_T] {
                    gl.tex_parameter_i32(glow::TEXTURE_2D, axis, glow::CLAMP_TO_EDGE as i32);
                }
                gl.tex_image_2d(
                    glow::TEXTURE_2D,
                    0,
                    glow::RGBA as i32,
                    card.image.width() as i32,
                    card.image.height() as i32,
                    0,
                    glow::RGBA,
                    glow::UNSIGNED_BYTE,
                    glow::PixelUnpackData::Slice(Some(card.image.as_raw())),
                );
                gl.generate_mipmap(glow::TEXTURE_2D);
                self.textures.push(texture);
            }
            gl.bind_texture(glow::TEXTURE_2D, None);
        }
        self.cards = cards;
        Ok(())
    }

    pub fn paint(&self, gl: &glow::Context, windows: &[(usize, Mat4, bool)]) {
        // SAFETY: eframe invokes this callback with its context current. The
        // painter restores its own GL state after custom callbacks.
        unsafe {
            gl.disable(glow::DEPTH_TEST);
            gl.disable(glow::CULL_FACE);
            gl.enable(glow::BLEND);
            gl.blend_func(glow::ONE, glow::ONE_MINUS_SRC_ALPHA);
            gl.use_program(Some(self.program));
            gl.bind_vertex_array(Some(self.vao));
            gl.active_texture(glow::TEXTURE0);
            gl.uniform_1_i32(gl.get_uniform_location(self.program, "image").as_ref(), 0);
            for &(index, transform, selected) in windows {
                if let Some(texture) = self.textures.get(index) {
                    gl.uniform_matrix_4_f32_slice(
                        gl.get_uniform_location(self.program, "transform").as_ref(),
                        false,
                        &transform.to_cols_array(),
                    );
                    gl.uniform_1_f32(
                        gl.get_uniform_location(self.program, "selected").as_ref(),
                        if selected { 1.0 } else { 0.0 },
                    );
                    let card = &self.cards[index];
                    gl.uniform_1_f32(
                        gl.get_uniform_location(self.program, "aspect").as_ref(),
                        card.aspect(),
                    );
                    gl.bind_texture(glow::TEXTURE_2D, Some(*texture));
                    gl.draw_arrays(glow::TRIANGLES, 0, 6);
                }
            }
            gl.bind_texture(glow::TEXTURE_2D, None);
            gl.bind_vertex_array(None);
            gl.use_program(None);
        }
    }

    pub fn destroy_borrowed(&mut self, gl: &glow::Context) {
        // SAFETY: eframe calls on_exit before releasing the GL context.
        unsafe {
            for texture in self.textures.drain(..) {
                gl.delete_texture(texture);
            }
            gl.delete_vertex_array(self.vao);
            gl.delete_program(self.program);
        }
    }
}
