// EVE Local Station build-only adaptation of upstream revision
// 5772f9d6238a019b71f0fb235fbeeaf1338694f5, 2026-09-08.
// Generate the same constants from the pinned YAML-derived mapping without
// requiring private .env files or full game data during compilation.
use std::{collections::BTreeMap, env, fs, io::Write, path::PathBuf};
use convert_case::{Case, Casing};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(feature = "protobuf")]
    {
        println!("cargo:rerun-if-changed=efos.proto");
        println!("cargo:rerun-if-env-changed=PROTOC");
        if env::var_os("PROTOC").is_none() {
            env::set_var("PROTOC", protoc_bin_vendored::protoc_bin_path()?);
        }
        prost_build::Config::new().compile_protos(&["efos.proto"], &["."])?;
    }
    println!("cargo:rerun-if-changed=patch_ids.json");
    let mapping: BTreeMap<String, BTreeMap<String, i32>> =
        serde_json::from_str(&fs::read_to_string("patch_ids.json")?)?;
    let out = PathBuf::from(env::var("OUT_DIR")?);
    for (kind, file_name, prefix) in [("attributes", "patch_attrs.rs", "ATTR"), ("effects", "patch_effects.rs", "EFFECT")] {
        let mut file = fs::File::create(out.join(file_name))?;
        for (name, id) in &mapping[kind] {
            assert!(*id < 0, "Patch identifiers must be negative");
            writeln!(file, "pub const {}_{}: i32 = {};", prefix, name.to_case(Case::Constant), id)?;
        }
    }
    Ok(())
}
