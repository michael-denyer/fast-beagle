#!/bin/bash
# Download the 1000 Genomes high-coverage chr20 panel and Beagle's GRCh38
# genetic map, verify checksums, and derive the benchmark inputs:
# ref.vcf.gz, target.vcf.gz and chr20.map, bgzip-compressed.
#
# Usage: tests/bench/fetch-chr20.sh <dir>  (about 1.5 GB when done)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1"
cd "$1"

PANEL=1kGP_high_coverage_Illumina.chr20.filtered.SNV_INDEL_SV_phased_panel.vcf.gz
fetch() {  # url dest sha256
  # An HTTP error or an interrupted download leaves no file at <dest>.
  if [ ! -f "$2" ]; then
    curl -fSL -o "$2.part" "$1" || { echo "FAIL download $1" >&2; exit 1; }
    mv "$2.part" "$2"
  fi
  echo "$3  $2" | shasum -a 256 -c -
}
fetch "https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage/working/20220422_3202_phased_SNV_INDEL_SV/$PANEL" \
  "$PANEL" 9e936fdf434a4aa4ff1d37c0d386a13a43a7211d4f09fb5da811ed6eb5125626
fetch https://bochet.gcc.biostat.washington.edu/beagle/genetic_maps/plink.GRCh38.map.zip \
  plink.GRCh38.map.zip 521549889b9ce0236142a4fb7db45d3f00035ec645e01465490d55f5b8ef26d6

unzip -o -p plink.GRCh38.map.zip no_chr_in_chrom_field/plink.chr20.GRCh38.map | sed 's/^20 /chr20 /' > chr20.map
python3 "$ROOT/tests/bench/make_chr20.py" "$PANEL" .
for f in ref target; do
  gzip -dc "$f.vcf.gz" | bgzip -c > "$f.bgz.vcf.gz"
  mv "$f.bgz.vcf.gz" "$f.vcf.gz"
done
