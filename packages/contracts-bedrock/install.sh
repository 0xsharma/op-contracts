#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Limpiando dependencias previas en lib/..."

deps=(
  "OpenZeppelin/openzeppelin-contracts@v4.9.3"
  "OpenZeppelin/openzeppelin-contracts@v5.0.2"
  "OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2"
  "Rari-Capital/solmate@main"
  "vectorized/solady@main"
  "vectorized/solady@v0.0.245"
  "safe-global/safe-contracts@v1.3.0"
  "bryanjos/libkeccak@main"
  "foundry-rs/forge-std@master"
)

for dep in "${deps[@]}"; do
  pkg="${dep%@*}"
  version="${dep#*@}"
  dir="lib/$(basename "$pkg")"

  # Si ya existe, lo renombramos con sufijo -old
  if [ -d "$dir" ]; then
    echo "⚠️  $dir ya existe, moviendo a ${dir}-old"
    mv "$dir" "${dir}-old-$(date +%s)"
  fi

  echo "⬇️ Instalando $pkg ($version)..."
  forge install "$dep"
done

echo "✅ Todas las dependencias instaladas."


