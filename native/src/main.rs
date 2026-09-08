use std::io::{self, Read};
fn main() {
    let mut request = String::new();
    io::stdin()
        .read_to_string(&mut request)
        .expect("read request JSON from stdin");
    println!("{}", eve_local_core::call_json(&request));
}
