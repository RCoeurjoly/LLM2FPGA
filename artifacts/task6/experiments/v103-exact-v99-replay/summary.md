{
  "bitstream": "/nix/store/qmzhnmwwybzmi2cyf3xncj3p1nirz46f-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit",
  "bitstream_sha256": "b02f9444f17ea595c45e6110867dbb4fe09bc9b4658af3bd7582eee629d0e116",
  "decision": {
    "next_gate": "do not change DDR logic; inspect DFII byte/source/read phase association before rerunning native BIST"
  },
  "hypothesis": "DFII byte/phase writes map to a fixed physical-to-logical byte/phase association",
  "init_state": "INIT_DONE",
  "mapping_inference": {
    "confidence": "low",
    "is_bijective": false,
    "matrix_shape": "16_write_slots_by_20_read_slots",
    "phase_transform": "source_phase=0, write_command_phase=3, read_phase=2; read_slot=word*4+byte",
    "physical_to_logical_byte": [
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null
    ]
  },
  "probe_complete": true,
  "probe_failed": true,
  "probe_state": "PROBE_DFII_DONE",
  "probe_version": 99,
  "raw_masks": {
    "match_high_nibbles": [
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x2",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0"
    ],
    "match_masks": [
      "0x00201",
      "0x00402",
      "0x00804",
      "0x01008",
      "0x02010",
      "0x04020",
      "0x08040",
      "0x00000",
      "0x20100",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000"
    ],
    "nonzero_high_nibbles": [
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x2",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0",
      "0x0"
    ],
    "nonzero_masks": [
      "0x00201",
      "0x00402",
      "0x00804",
      "0x01008",
      "0x02010",
      "0x04020",
      "0x08040",
      "0x00000",
      "0x20100",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000",
      "0x00000"
    ]
  },
  "status": "FAIL",
  "status_flags": {
    "cmd_ready": true,
    "init_done": true,
    "init_error": false,
    "init_seq_done": true,
    "init_seq_error": false,
    "init_seq_running": false,
    "outstanding_full": false,
    "pll_locked": true,
    "rdata_valid": false,
    "read_target_issued": false,
    "read_target_seen": false,
    "sys_rstn": true,
    "timeout_seen": false,
    "user_rst": false,
    "wb_error_seen": false,
    "wb_timeout_seen": false
  },
  "write_cases": [
    {
      "observed": "0x00201",
      "observed_match_slots": [
        0,
        9
      ],
      "observed_nonzero_mask": "0x00201",
      "observed_nonzero_slots": [
        0,
        9
      ],
      "pattern": "0xa0",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 0,
      "write_byte": 0,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 0
    },
    {
      "observed": "0x00402",
      "observed_match_slots": [
        1,
        10
      ],
      "observed_nonzero_mask": "0x00402",
      "observed_nonzero_slots": [
        1,
        10
      ],
      "pattern": "0xa1",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 0,
      "write_byte": 1,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 1
    },
    {
      "observed": "0x00804",
      "observed_match_slots": [
        2,
        11
      ],
      "observed_nonzero_mask": "0x00804",
      "observed_nonzero_slots": [
        2,
        11
      ],
      "pattern": "0xa2",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 0,
      "write_byte": 2,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 2
    },
    {
      "observed": "0x01008",
      "observed_match_slots": [
        3,
        12
      ],
      "observed_nonzero_mask": "0x01008",
      "observed_nonzero_slots": [
        3,
        12
      ],
      "pattern": "0xa3",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 0,
      "write_byte": 3,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 3
    },
    {
      "observed": "0x02010",
      "observed_match_slots": [
        4,
        13
      ],
      "observed_nonzero_mask": "0x02010",
      "observed_nonzero_slots": [
        4,
        13
      ],
      "pattern": "0xa4",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 1,
      "write_byte": 0,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 4
    },
    {
      "observed": "0x04020",
      "observed_match_slots": [
        5,
        14
      ],
      "observed_nonzero_mask": "0x04020",
      "observed_nonzero_slots": [
        5,
        14
      ],
      "pattern": "0xa5",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 1,
      "write_byte": 1,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 5
    },
    {
      "observed": "0x08040",
      "observed_match_slots": [
        6,
        15
      ],
      "observed_nonzero_mask": "0x08040",
      "observed_nonzero_slots": [
        6,
        15
      ],
      "pattern": "0xa6",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 1,
      "write_byte": 2,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 6
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xa7",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 1,
      "write_byte": 3,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 7
    },
    {
      "observed": "0x20100",
      "observed_match_slots": [
        8,
        17
      ],
      "observed_nonzero_mask": "0x20100",
      "observed_nonzero_slots": [
        8,
        17
      ],
      "pattern": "0xa8",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 2,
      "write_byte": 0,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 8
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xa9",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 2,
      "write_byte": 1,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 9
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xaa",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 2,
      "write_byte": 2,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 10
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xab",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 2,
      "write_byte": 3,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 11
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xac",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 3,
      "write_byte": 0,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 12
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xad",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 3,
      "write_byte": 1,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 13
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xae",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 3,
      "write_byte": 2,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 14
    },
    {
      "observed": "0x00000",
      "observed_match_slots": [],
      "observed_nonzero_mask": "0x00000",
      "observed_nonzero_slots": [],
      "pattern": "0xaf",
      "read_beat": null,
      "read_logical_byte": null,
      "read_phase": null,
      "read_slot": null,
      "write_beat": 3,
      "write_byte": 3,
      "write_command_phase": 3,
      "write_phase": 0,
      "write_slot": 15
    }
  ]
}

## Reproducibility note

This v103 replay was built from detached worktree commit `cecae7b`, the recorded v99 result snapshot. The rebuilt bitstream is bit-for-bit identical to the original v99 bitstream:

- bitstream: `/nix/store/qmzhnmwwybzmi2cyf3xncj3p1nirz46f-task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.bit`
- sha256: `b02f9444f17ea595c45e6110867dbb4fe09bc9b4658af3bd7582eee629d0e116`

Hardware replay restored the clean execution state:

- `version=99`
- `pll_locked=true`
- `init_done=true`
- `init_error=false`
- `init_seq_done=true`
- `init_seq_error=false`
- `wb_timeout_seen=false`
- `state=PROBE_DFII_DONE`

The combined 20-slot matrix is reproduced:

```text
source0  0x00201
source1  0x00402
source2  0x00804
source3  0x01008
source4  0x02010
source5  0x04020
source6  0x08040
source7  0x00000
source8  0x20100
source9  0x00000
source10 0x00000
source11 0x00000
source12 0x00000
source13 0x00000
source14 0x00000
source15 0x00000
```
