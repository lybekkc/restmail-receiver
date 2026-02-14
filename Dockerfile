# Bruk den nyeste stabile versjonen
FROM rust:latest AS builder

WORKDIR /app
COPY . .

# Vi sletter lock-filen inne i containeren for å la Cargo 
# løse avhengighetene på nytt basert på denne Rust-versjonen
RUN rm -f Cargo.lock && cargo build --release

# Stage 2: Runtime
FROM debian:bookworm-slim
WORKDIR /app

# Vi må installere CA-sertifikater i tilfelle appen din skal snakke med andre API-er
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/restmail-receiver /app/restmail-receiver

EXPOSE 2525
CMD ["./restmail-receiver"]
