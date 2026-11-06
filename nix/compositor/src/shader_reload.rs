//! Explicit checkout shader overrides for nested development previews.
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};

#[derive(Clone, PartialEq, Debug)]
pub struct Sources {
    pub rounded: String,
    pub coverage: String,
    pub frame: String,
    pub frost: String,
    pub shadow: String,
}
impl Sources {
    pub fn load(directory: Option<&std::path::Path>) -> anyhow::Result<Self> {
        let read = |name, embedded: &str| -> anyhow::Result<String> {
            match directory {
                Some(directory) => Ok(std::fs::read_to_string(directory.join(name))?),
                None => Ok(embedded.to_owned()),
            }
        };
        Ok(Self {
            rounded: read("rounded.frag", include_str!("rounded.frag"))?,
            coverage: read(
                "rounded-coverage.glsl",
                include_str!("rounded-coverage.glsl"),
            )?,
            frame: read("frame.frag", include_str!("frame.frag"))?,
            frost: read("frost.frag", include_str!("frost.frag"))?,
            shadow: read("shadow.frag", include_str!("shadow.frag"))?,
        })
    }
    pub fn configured() -> anyhow::Result<Self> {
        let directory = std::env::var_os("OHMANSY_SHINE_SHADER_DIR").map(PathBuf::from);
        Self::load(directory.as_deref())
    }
}

pub struct Watch {
    directory: PathBuf,
    last: Result<Sources, String>,
    next: Instant,
}
impl Watch {
    pub fn configured() -> anyhow::Result<Option<Self>> {
        std::env::var_os("OHMANSY_SHINE_SHADER_DIR")
            .map(|directory| {
                let directory = PathBuf::from(directory);
                Ok(Self {
                    last: Ok(Sources::load(Some(&directory))?),
                    directory,
                    next: Instant::now(),
                })
            })
            .transpose()
    }
    pub fn changed(&mut self, now: Instant) -> bool {
        if now < self.next {
            return false;
        }
        self.next = now + Duration::from_millis(250);
        let loaded = Sources::load(Some(&self.directory)).map_err(|e| e.to_string());
        if self.last == loaded {
            return false;
        }
        self.last = loaded;
        match &self.last {
            Ok(_) => true,
            Err(error) => {
                eprintln!("Shine shader reload rejected: {error}; keeping working shaders");
                false
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checkout_edits_missing_files_and_recovery_are_observed_without_gpu_work() {
        let directory = std::env::temp_dir().join(format!(
            "shine-shader-watch-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&directory).unwrap();
        for file in [
            "rounded.frag",
            "rounded-coverage.glsl",
            "frame.frag",
            "frost.frag",
            "shadow.frag",
        ] {
            std::fs::write(directory.join(file), file).unwrap();
        }
        let now = Instant::now();
        let mut watch = Watch {
            last: Ok(Sources::load(Some(&directory)).unwrap()),
            directory: directory.clone(),
            next: now,
        };
        assert!(!watch.changed(now));
        std::fs::write(directory.join("frame.frag"), "edited frame").unwrap();
        assert!(watch.changed(now + Duration::from_secs(1)));
        assert!(!watch.changed(now + Duration::from_secs(2)));
        std::fs::remove_file(directory.join("shadow.frag")).unwrap();
        assert!(!watch.changed(now + Duration::from_secs(3)));
        std::fs::write(directory.join("shadow.frag"), "recovered shadow").unwrap();
        assert!(watch.changed(now + Duration::from_secs(4)));
        std::fs::remove_dir_all(directory).unwrap();
    }
}
