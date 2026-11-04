use glam::{Mat4, Vec3, Vec4};

#[derive(Clone, Copy)]
pub struct Settings {
    pub scale: f32,
    pub depth: f32,
    pub tilt: f32,
    pub distance: f32,
    pub spread: f32,
    pub orbit: f32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            scale: 1.0,
            depth: 1.1,
            tilt: 48.0,
            distance: 7.0,
            spread: 2.7,
            orbit: 0.0,
        }
    }
}

pub fn transform(settings: Settings, aspect: f32, viewport: f32, offset: f32) -> Mat4 {
    let width = 4.2 * settings.scale;
    let height = width / aspect.max(0.2);
    let model = Mat4::from_translation(Vec3::new(
        offset * settings.spread,
        -offset.abs() * 0.06,
        -offset.abs() * settings.depth,
    )) * Mat4::from_rotation_y(
        (settings.orbit - offset.clamp(-1.0, 1.0) * settings.tilt).to_radians(),
    ) * Mat4::from_scale(Vec3::new(width, height, 1.0));
    let view = Mat4::from_translation(Vec3::new(0.0, 0.0, -settings.distance));
    Mat4::perspective_rh_gl(45.0_f32.to_radians(), viewport.max(0.1), 0.1, 100.0) * view * model
}

/// Transform a screen-space pointer ray back into the window's local plane.
pub fn hit(mvp: Mat4, ndc_x: f32, ndc_y: f32) -> bool {
    let inverse = mvp.inverse();
    let near = inverse * Vec4::new(ndc_x, ndc_y, -1.0, 1.0);
    let far = inverse * Vec4::new(ndc_x, ndc_y, 1.0, 1.0);
    let near = near.truncate() / near.w;
    let far = far.truncate() / far.w;
    let direction = far - near;
    if direction.z.abs() < 1e-6 {
        return false;
    }
    let t = -near.z / direction.z;
    let point = near + t * direction;
    (0.0..=1.0).contains(&t) && point.x.abs() <= 0.5 && point.y.abs() <= 0.5
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picking_follows_perspective_and_rejects_outside_edges() {
        for scale in [0.75, 1.0, 1.5, 2.0] {
            for offset in [-2.0, -1.0, 0.0, 1.0, 2.0] {
                let mvp = transform(
                    Settings {
                        scale,
                        ..Settings::default()
                    },
                    1.6,
                    1.8,
                    offset,
                );
                for (x, y, expected) in [(0.0, 0.0, true), (0.4, 0.4, true), (0.6, 0.0, false)] {
                    let p = mvp * Vec4::new(x, y, 0.0, 1.0);
                    assert_eq!(hit(mvp, p.x / p.w, p.y / p.w), expected);
                }
            }
        }
    }

    #[test]
    fn increasing_depth_makes_side_windows_smaller() {
        let projected_width = |depth| {
            let mvp = transform(
                Settings {
                    depth,
                    tilt: 0.0,
                    ..Settings::default()
                },
                1.6,
                1.8,
                1.0,
            );
            let a = mvp * Vec4::new(-0.5, 0.0, 0.0, 1.0);
            let b = mvp * Vec4::new(0.5, 0.0, 0.0, 1.0);
            b.x / b.w - a.x / a.w
        };
        assert!(projected_width(2.0) < projected_width(0.0));
    }
}
