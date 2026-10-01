# Third-party notice: XAERO-02

The SimuVerity task specification, wrapper, and packaging code are covered by the repository license. Reference assets remain under their upstream terms; the repository license does not replace those terms.

Reference materialization: `bundled`.

The optional ArduPilot SITL library retains the upstream archive and model
content. Three `SourceProductName` metadata strings in its Simulink
`blockdiagram.xml` were normalized from a host-specific MATLAB installation
path to the host-neutral `simulink/` prefix; no model logic or interface was
changed.

Upstream metadata:

- owner: Institute of Flight Guidance, Technische Universität Braunschweig (iff-gsc)
- title: LADAC-Examples / LindiPlane conventional airplane example
- source_url: https://github.com/iff-gsc/LADAC-Examples

Included license/notice files:

- `reference/files/LICENSE`
- `reference/files/modules/ladac-examples-data/LICENSE`
- `reference/files/modules/ladac/LICENSE`
- `reference/files/modules/ladac/libraries/qcat/license.txt`
- `reference/files/modules/ladac/libraries/MatlabInputRelease/LICENSE`
- `reference/files/modules/ladac/libraries/m-utils/LICENSE`
- `reference/files/modules/ladac/libraries/3DScope/license.txt`
