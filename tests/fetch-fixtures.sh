#!/bin/bash
# Download Beagle's public test data and release jars, verify checksums, and
# derive the fixtures that the case tables tests/*-cases.txt run.
# --ensure reuses fixtures only while the recipe, case tables and every
# recorded input still match. Without it, regenerate the derived fixtures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DATA="$ROOT/data"
MANIFEST="$DATA/.fixtures.sha256"
if [ "${1:-}" = --ensure ] && [ -f "$MANIFEST" ] \
    && (cd "$ROOT" && shasum -a 256 --status -c "$MANIFEST"); then
  exit 0
fi
mkdir -p "$DATA"
# A failed or interrupted generation cannot leave a valid readiness stamp.
rm -f "$MANIFEST"
cd "$DATA"

# The bref3 fixtures need a JDK. macOS has a /usr/bin/java that only prints
# how to install one, so run it rather than look for it.
java -version > /dev/null 2>&1 || {
  echo "FAIL java cannot run, and the bref3 fixtures need it: put a JDK first on PATH" >&2
  exit 1
}

BASE=https://faculty.washington.edu/browning/beagle
fetch() {  # url dest sha256
  # An HTTP error or an interrupted download leaves no file at <dest>.
  if [ ! -f "$2" ]; then
    curl -fSL -o "$2.part" "$1" || { echo "FAIL download $1" >&2; exit 1; }
    mv "$2.part" "$2"
  fi
  echo "$3  $2" | shasum -a 256 -c -
}
fetch "$BASE/test.beagle.vcf.gz" test.vcf.gz 8200f512645c4ac271777bdf20b045d592774dc58e7517885df4627340b184e6
fetch "$BASE/beagle.27Feb25.75f.jar" beagle.27Feb25.75f.jar 7319f4af9638be05c18dcc1bfb8fb41a58a09293507ebf0d54617d0e40df5a70
fetch "$BASE/bref3.27Feb25.75f.jar" bref3.27Feb25.75f.jar 6166426f63b2c1cfed9e2cda2f9ba59ef3b3c19fdfc988a9ec6036358457e3f2

# Same split as Beagle's run.beagle example: 181 reference samples, 10 targets.
split_panel() {  # source.vcf.gz suffix
  gzip -dc "$1" | cut -f1-190 | tr '/' '|' | gzip > "ref$2.vcf.gz"
  gzip -dc "$1" | cut -f1-9,191-200 | gzip > "target$2.vcf.gz"
  # Keep every 10th target marker so the rest are imputed.
  gzip -dc "target$2.vcf.gz" | awk '/^#/ {print; next} {n++; if (n % 10 == 1) print}' | gzip > "target$2.thin.vcf.gz"
}
split_panel test.vcf.gz ""

# chrX: the first 90 reference samples and the first 5 targets are haploid.
gzip -dc test.vcf.gz | awk 'BEGIN {OFS="\t"} /^#/ {print; next} {
  $1 = "X"
  for (c = 10; c <= NF; c++) if (c < 100 || (c >= 191 && c < 196)) sub(/[\/|][^:]*/, "", $c)
  print }' | gzip > test.X.vcf.gz
split_panel test.X.vcf.gz .X

# The chrX split on chromosome 22 and the plain split on chromosome 38
# (tests/bgen-cases.txt).
move_chrom() {  # in.vcf.gz chrom out.vcf.gz
  gzip -dc "$1" | awk -v c="$2" 'BEGIN {OFS="\t"} /^#/ {print; next} {$1 = c; print}' | gzip > "$3"
}
move_chrom ref.X.vcf.gz 22 ref.hap22.vcf.gz
move_chrom target.X.thin.vcf.gz 22 target.hap22.thin.vcf.gz
move_chrom ref.vcf.gz 38 ref.chr38.vcf.gz
move_chrom target.thin.vcf.gz 38 target.chr38.thin.vcf.gz

# Multiallelic: every 7th SNV gains a third allele, carried by a deterministic
# subset of the samples that carry the first ALT allele.
gzip -dc test.vcf.gz | awk 'BEGIN {OFS="\t"} /^#/ {print; next} {
  n++
  if (n % 7 == 0 && length($4) == 1 && length($5) == 1) {
    for (i = 1; i <= 4; i++) { b = substr("ACGT", i, 1); if (b != $4 && b != $5) break }
    $5 = $5 "," b
    for (c = 10; c <= NF; c++) {
      split($c, f, ":")
      if ((n + c) % 3 == 0) sub(/1/, "2", f[1])
      $c = f[1]
    }
    $9 = "GT"
  }
  print }' | gzip > test.multi.vcf.gz
split_panel test.multi.vcf.gz .multi

# Missing genotypes at a deterministic 1 in 23 of target genotypes.
missing() {  # in.vcf.gz out.vcf.gz
  gzip -dc "$1" | awk 'BEGIN {OFS="\t"} /^#/ {print; next} {
    n++
    for (c = 10; c <= NF; c++) if ((n * 31 + c * 17) % 23 == 0) sub(/^[^:]*/, "./.", $c)
    print }' | gzip > "$2"
}
missing test.vcf.gz test.miss.vcf.gz
missing target.thin.vcf.gz target.thin.miss.vcf.gz

# No target markers from 20.03 to 20.08 Mb, so one imputation cluster spans
# 740 reference markers, more than the imputed writer builds in one piece.
gzip -dc target.thin.vcf.gz | awk '/^#/ || $2 < 20030000 || $2 >= 20080000' | gzip > target.gap.vcf.gz

# PLINK map with a recombination rate of 20 cM/Mb up to 20.05 Mb and 80 cM/Mb
# after, so the 100 kb region spans 5 cM and splits into several windows.
gzip -dc test.vcf.gz | awk '!/^#/ && ++n % 25 == 1 {
  x = ($2 - 20000000) / 1e6
  cm = x <= 0.05 ? 20 * x : 1 + 80 * (x - 0.05)
  printf "22\t%s\t%.6f\t%s\n", $3, cm, $2 }' > map.map

# Integer.parseInt reads decimal digits of any script. Every 10th POS is in
# Arabic-Indic digits and every 10th from the fifth in fullwidth digits, the
# first sample's GT alleles in every 7th record are two Arabic-Indic digits
# (Beagle reads a one-character allele as c - '0'), and every 3rd map base
# position is in Arabic-Indic digits. The numbers are unchanged, so Beagle
# writes the output of the same run on test.vcf.gz and map.map.
DIGITS='function digits(n, script,   s, i) {
    s = ""
    for (i = 1; i <= length(n); i++) s = s script[substr(n, i, 1)]
    return s
  }
  BEGIN {
    OFS = "\t"
    for (d = 0; d < 10; d++) { arabic[d] = sprintf("%c%c", 217, 160 + d); fullwidth[d] = sprintf("%c%c%c", 239, 188, 144 + d) }
  }'
gzip -dc test.vcf.gz | LC_ALL=C awk "$DIGITS"' /^#/ {print; next} {
  n++
  if (n % 10 == 0) $2 = digits($2, arabic)
  if (n % 10 == 5) $2 = digits($2, fullwidth)
  if (n % 7 == 0 && $10 ~ /^[0-9]\/[0-9]:/) $10 = digits(0 substr($10, 1, 1), arabic) "/" digits(0 substr($10, 3, 1), arabic) substr($10, 4)
  print }' | gzip > test.udigit.vcf.gz
LC_ALL=C awk "$DIGITS"' NR % 3 == 0 {$4 = digits($4, arabic)} {print}' map.map > map.udigit.map

# Exclusions: every 10th sample and every 13th named marker.
gzip -dc test.vcf.gz | awk '/^#CHROM/ {for (c = 10; c <= NF; c += 10) print $c}' > exclude.samples
gzip -dc test.vcf.gz | awk '!/^#/ && $3 != "." && ++n % 13 == 0 {print $3}' > exclude.markers

java -jar bref3.27Feb25.75f.jar ref.vcf.gz > ref.bref3
java -jar bref3.27Feb25.75f.jar ref.multi.vcf.gz > ref.multi.bref3
# END= in the INFO of every 25th record, SNV or not, and a second ID on every
# 31st. bref3 keeps END only for markers that are not SNVs, so imputed SNVs
# print it from a VCF reference but not from this bref3 file.
gzip -dc ref.vcf.gz | awk 'BEGIN {OFS="\t"} /^#/ {print; next} {
  n++
  if (n % 25 == 0) $8 = "END=" ($2 + length($4) - 1) ";" $8
  if (n % 31 == 0 && $3 != ".") $3 = $3 ";alt" n
  print }' | java -jar bref3.27Feb25.75f.jar > ref.end.bref3

# Several chromosomes: the reference adds chromosome 21 (absent from the
# target) before 22, and 23 after it. The target adds one marker absent from
# the reference and changes the ALT allele of another, so both are dropped.
# With impute=false Beagle 5.5 fails on this file: the unread reference-only
# record at the end of chromosome 22 keeps window 1 from ending the
# chromosome, so window 2 spans two chromosomes (tests/trace-cases.txt).
relabel() {  # in.vcf.gz chrom first-n-records
  gzip -dc "$1" | awk -v c="$2" -v n="$3" 'BEGIN {OFS="\t"} !/^#/ && ++k <= n {$1 = c; print}'
}
{
  gzip -dc ref.vcf.gz | grep '^#'
  relabel ref.vcf.gz 21 50
  gzip -dc ref.vcf.gz | grep -v '^#'
  relabel ref.vcf.gz 23 300
} | gzip > ref.chroms.vcf.gz
{
  gzip -dc target.thin.vcf.gz | grep '^#'
  gzip -dc target.thin.vcf.gz | awk 'BEGIN {OFS="\t"} !/^#/ {
    n++
    if (n == 3) { print; $2 = $2 + 1; $3 = "extra"; print; next }
    if (n == 5) { for (i = 1; i <= 4; i++) { b = substr("ACGT", i, 1); if (b != $4 && b != $5) break }; $5 = b }
    print }'
  relabel target.thin.vcf.gz 23 30
} | gzip > target.chroms.vcf.gz

# IBS2: three added samples share both haplotypes with others. DUP1 copies
# the first sample, CHIM23 copies the second before 20.07 Mb and the third
# after, and BRK4 copies the fourth except for opposite homozygotes between
# 20.040 and 20.042 Mb. map.steep.map (300 cM/Mb) spreads the region over
# 30 cM in one window, so the IBS2 markers fall into several steps.
gzip -dc test.vcf.gz | awk 'BEGIN {OFS="\t"} /^##/ {print; next}
  /^#CHROM/ {print $0, "DUP1", "CHIM23", "BRK4"; next} {
    brk = $13
    if ($2 >= 20040000 && $2 <= 20042000) brk = ($13 ~ /^0\/0/) ? "1/1" : "0/0"
    print $0, $10, ($2 < 20070000 ? $11 : $12), brk }' | gzip > test.ibs2.vcf.gz
gzip -dc test.vcf.gz | awk '!/^#/ && ++n % 25 == 1 {
  printf "22\t%s\t%.6f\t%s\n", $3, 300 * ($2 - 20000000) / 1e6, $2 }' > map.steep.map
# The IBS2 fixture with missing genotypes: 1 in 10 at every 5th marker (near
# the 10% limit for IBS2 markers), 1 in 23 elsewhere, and every 4th marker for
# the eleventh sample (over the 10% limit per step).
gzip -dc test.ibs2.vcf.gz | awk 'BEGIN {OFS="\t"} /^#/ {print; next} {
  n++
  for (c = 10; c <= NF; c++) if ((n * 31 + c * 17) % (n % 5 == 0 ? 10 : 23) == 0 || (c == 20 && n % 4 == 0)) sub(/^[^:]*/, "./.", $c)
  print }' | gzip > test.ibs2.miss.vcf.gz

# Every marker in stage 1: FixedPhaseData skips stage 2 when more than 75% of
# a window's markers, or fewer than 2, have two alleles carried by more than
# 3 samples. test.common keeps the markers with ALT frequency in [0.05, 0.95]
# and every 10th other marker (424 markers). test.rare keeps the markers whose
# REF or ALT allele is carried by at most 3 samples, plus the first other
# marker (955 markers).
gzip -dc test.vcf.gz | awk '/^#/ {print; next} {
  n = alt = 0
  for (c = 10; c <= NF; c++) {
    split($c, f, ":"); k = split(f[1], a, "[/|]")
    for (i = 1; i <= k; i++) if (a[i] != ".") { n++; alt += a[i] != "0" }
  }
  if (n > 0 && alt / n >= 0.05 && alt / n <= 0.95) print; else if (++other % 10 == 0) print }' | gzip > test.common.vcf.gz
gzip -dc test.vcf.gz | awk '/^#/ {print; next} {
  r = x = 0
  for (c = 10; c <= NF; c++) { g = substr($c, 1, 3); r += g ~ /0/; x += g ~ /1/ }
  if (r <= 3 || x <= 3 || !common++) print }' | gzip > test.rare.vcf.gz

# A reference of 28 copies of the 181 reference samples (more than 10,000
# haplotypes) over the first 300 markers, with the 10 targets on those markers.
gzip -dc ref.vcf.gz | awk 'BEGIN {OFS="\t"} /^##/ {print; next} {
  if (!/^#CHROM/ && ++n > 300) next
  line = $1; for (c = 2; c <= 9; c++) line = line OFS $c
  for (k = 1; k <= 28; k++) for (c = 10; c <= NF; c++) line = line OFS (/^#CHROM/ ? $c "_" k : $c)
  print line }' | gzip > ref.big.vcf.gz
gzip -dc target.vcf.gz | awk '/^#/ {print; next} ++n <= 300' | gzip > target.300.vcf.gz

# More than 500 target samples, so parameter estimation uses a random 500:
# three copies of the panel's 191 samples over the first 200 markers.
gzip -dc test.vcf.gz | awk 'BEGIN {OFS="\t"} /^##/ {print; next} {
  if (!/^#CHROM/ && ++n > 200) next
  line = $1; for (c = 2; c <= 9; c++) line = line OFS $c
  for (k = 1; k <= 3; k++) for (c = 10; c <= NF; c++) line = line OFS (/^#CHROM/ ? $c "_" k : $c)
  print line }' | gzip > test.573.vcf.gz

# Dense markers: 600 SNVs 10 bp apart, mostly homozygous, so runs of
# homozygotes within 0.005 cM reach SamplePhase's 255-marker cluster limit.
{
  printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT'
  for s in $(seq 1 10); do printf '\tD%d' "$s"; done
  printf '\n'
  for k in $(seq 0 599); do
    printf '1\t%d\t.\tA\tC\t.\t.\t.\tGT' $((1000 + 10 * k))
    for s in $(seq 1 10); do
      if [ $(((k * 7 + s * 13) % 331)) -eq 0 ]; then printf '\t0/1'
      elif [ $(((k + s) % 2)) -eq 0 ]; then printf '\t0/0'
      else printf '\t1/1'; fi
    done
    printf '\n'
  done
} | gzip > edge-dense.vcf.gz

# Trace-only edge cases for input parsing (tests/trace-cases.txt).
edge_header() {
  printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS2\n'
}
{
  edge_header
  printf '1\t100\trs1;rs2\tA\tC\t.\tPASS\t.\tGT\t0/1\t1/1\n'
  printf '1\t150\t.\tA\tC,\t.\t.\t.\tGT\t0/1\t0/0\n'
  printf '1\t200\t\tA\tC\t.\t.\tEND=250\tGT\t0/1\t0/0\n'
  printf '1\t300\trs3\tAC\tA,ACC\t.\t.\tXEND=5;END=320;END=330\tGT\t0/1\t2/1\n'
  printf '1\t400\trs4\tG\t.\t.\t.\t.\tGT\t0/0\t0/0\n'
  printf '1\t500\trs5\tT\tG\t.\t.\tEND=\tGT\t0/1\t0/0\n'
  printf '2\t100\trs6\tTTT\tT\t.\t.\t.\tGT\t0|1\t1|0\n'
} | gzip > edge-markers.vcf.gz
{
  edge_header
  printf '1\t100\trs1\tA\tC\t.\t.\t.\tGT\t0/1\t1/1\r\n'
  printf '1\t200\trs2\tA\tG\t.\t.\t.\tGT\t0/0\t0/1\r\n'
} | gzip > edge-crlf.vcf.gz
{
  edge_header
  printf '1\t100\trs\351\tA\tC\t.\t.\t.\tGT\t0/1\t1/1\n'
  printf '1\t200\trs2\tA\tG\t.\t.\t.\tGT\t0/0\t0/1\n'
} | gzip > edge-latin1.vcf.gz
{
  edge_header
  printf '1\t100\trs1\tA\tC\t.\t.\t.\tGT\t0/1\t1/1\n'
  printf '1\t200\trs2\tA\tG\t.\t.\t.\tGT\t0/0\t0/1\n'
  printf '1\t300\trs3\tA\tT\t.\t.\t.\tGT\t0/1\t0/1'
} | bgzip > edge-noeol.vcf.gz
# bref3 edge cases: IDs with a 4-byte UTF-8 character (a surrogate pair in
# Java's modified UTF-8), an invalid byte and two entries, END= on SNV and
# other markers, a 3-allele SNV, a marker with no ALT allele and a symbolic
# allele.
{
  printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tR1\tR2\tR3\n'
  printf '1\t100\trs\360\237\230\200\tA\tC\t.\t.\tEND=100\tGT\t0|1\t1|1\t0|0\n'
  printf '1\t120\trs\351\tA\tT\t.\t.\t.\tGT\t0|1\t0|0\t0|0\n'
  printf '1\t150\trs\303\251;rs2\tA\tC,G\t.\t.\t.\tGT\t0|2\t1|0\t0|0\n'
  printf '1\t200\t.\tAC\tA\t.\t.\tEND=201\tGT\t0|1\t0|0\t1|0\n'
  printf '1\t250\trs4\tG\t.\t.\t.\t.\tGT\t0|0\t0|0\t0|0\n'
  printf '1\t300\trs5\tT\t<DEL>\t.\t.\tSVTYPE=DEL;END=400\tGT\t0|1\t0|0\t0|0\n'
  printf '1\t350\trs6\tC\tT\t.\t.\t.\tGT\t1|0\t0|1\t0|0\n'
} | java -jar bref3.27Feb25.75f.jar > edge-bref3.bref3
{
  printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tT1\n'
  printf '1\t100\t.\tA\tC\t.\t.\t.\tGT\t0/1\n'
  printf '1\t350\t.\tC\tT\t.\t.\t.\tGT\t0/1\n'
} | gzip > edge-bref3-target.vcf.gz

# Imputation with err=0 where no reference haplotype carries the target's ALT
# alleles: every state probability is 0, so Beagle writes the imputed marker at
# 2000 with AF=NaN.
{
  printf '##fileformat=VCFv4.2\n##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">\n'
  printf '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n'
  printf '20\t1000\t.\tA\tC\t.\tPASS\t.\tGT\t1|1\n'
  printf '20\t3000\t.\tA\tC\t.\tPASS\t.\tGT\t1|1\n'
} | gzip > target.nan.vcf.gz
{
  printf '##fileformat=VCFv4.2\n##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">\n'
  printf '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tR1\tR2\n'
  printf '20\t1000\t.\tA\tC\t.\tPASS\t.\tGT\t0|0\t0|0\n'
  printf '20\t2000\t.\tA\tC\t.\tPASS\t.\tGT\t0|1\t1|0\n'
  printf '20\t3000\t.\tA\tC\t.\tPASS\t.\tGT\t0|0\t0|0\n'
} | gzip > ref.nan.vcf.gz

# Paths relative to the checkout let a complete cache move between worktrees.
# Publish only after every generator and checksum above has succeeded.
(cd "$ROOT" && shasum -a 256 tests/fetch-fixtures.sh tests/oracle-cases.txt tests/trace-cases.txt tests/bgen-cases.txt \
  data/*.vcf.gz data/*.bref3 data/*.map data/exclude.* data/*.jar) > "$MANIFEST.part"
mv "$MANIFEST.part" "$MANIFEST"
