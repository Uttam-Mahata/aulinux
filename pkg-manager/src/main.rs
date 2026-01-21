use clap::Parser;
use aupkg::commands::{Cli, execute};

fn main() {
    let cli = Cli::parse();

    if let Err(e) = execute(cli) {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
