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

# Create storage directory
RUN mkdir -p /var/mail/restmail/incoming

COPY --from=builder /app/target/release/restmail-receiver /app/restmail-receiver

# Set default environment variables (can be overridden at runtime)
ENV RESTMAIL_POLICY_PORT=12345
ENV RESTMAIL_DELIVERY_PORT=2525
ENV RESTMAIL_LISTEN_ADDRESS=0.0.0.0
ENV RESTMAIL_STORAGE_BASE_PATH=/var/mail/restmail
ENV RESTMAIL_STORAGE_INCOMING=incoming

EXPOSE 2525 12345
CMD ["./restmail-receiver"]
