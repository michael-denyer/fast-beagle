# Phasing and imputation

Beagle estimates phased haplotypes and missing alleles from target genotypes
and an optional reference panel.

## Language

**Output record**:
One marker's alleles, annotations and sample estimates. Its VCF and BGEN forms
describe the same samples in the same order.

**Dosage**:
The expected number of copies of an allele in a sample. The VCF prints dosages
rounded. Phased haplotype probabilities keep the information from before that rounding.

**Composite haplotype**:
A sequence assembled from segments of reference or target haplotypes and used
as a candidate copying sequence during phasing or imputation.

**IBS step**:
A group of adjacent markers used to find haplotypes that match the target.
A composite haplotype may change its source between two such observations.
