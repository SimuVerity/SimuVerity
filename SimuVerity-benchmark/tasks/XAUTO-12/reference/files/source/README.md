# Multi-Agent Obstacle Avoidance using Velocity Obstacles and Control Barrier Functions (ICRA 2025)

[![arXiv: 2409.10117v2](https://img.shields.io/badge/arXiv-2409.10117v2-B31B1B.svg)](https://arxiv.org/abs/2409.10117v2)
[![Video on YouTube](https://img.shields.io/badge/YouTube-Video-red.svg)](https://www.youtube.com/watch?v=Ox8v2s17gLw&ab_channel=AlejandroS%C3%A1nchezRoncero)

*Alejandro Sánchez Roncero, Rafael I. Cabral Muchacho, and Petter Ögren*  

![relaxed_vs_strict_white](https://github.com/user-attachments/assets/3430f579-d09b-405e-acd4-d905e3a39de0)

---

This repository contains the MATLAB code used for the experiments in the study "**Multi-Agent Obstacle Avoidance using Velocity Obstacles and Control Barrier Functions**."

## Overview

This project provides a MATLAB implementation that:
- Uses Velocity Obstacles (VO) for guidance as a relaxed constraint in the optimization objective.
- Guarantees safety through a Control Barrier Function (CBF) constraint.
- Works with both second-order integrator dynamics and car-like dynamics.

There are two major folders—one for second-order integrator dynamics and another for car-like dynamics. Each folder has the same structure:
- **`h_cbf_system.m`**: Main file implementing the collision avoidance algorithm, including all methods and the optimization problem.
- **`run_scenario.m`**: Helper script to run simulations, with parameters specified in `sim_config.m`.
- **`scenarios/`**: Folder containing various scenarios. Each scenario is constructed as a Simulink file.

If you encounter any issues with the code or have suggestions for improvement, please create a pull request or email [alesr@kth.se](mailto:alesr@kth.se). Note that the same method can be applied to more complex dynamical systems.

## Requirements

- **MATLAB**
- **Simulink** and **Simulink 3D Animation**  
- **Symbolic Math Toolbox** (used by `generate_functions.m` to create methods stored in `generated_functions/`. If you do not have this toolbox, you can implement those methods manually.)

## How to Run the Code

1. **Open MATLAB** and set the current folder to the folder corresponding to the dynamics you want to simulate.
2. **Configure `sim_config.m`** with the desired settings for the experiments.
3. **Run `run_scenario.m`** to start the simulation.

## Warnings

By default, all demo videos are recorded at a high frame rate, which can result in large file sizes.

## Citation

If you use this code in your research, please cite the associated work:

```bibtex
@misc{roncero2024multiagentobstacleavoidanceusing,
      title={Multi-Agent Obstacle Avoidance using Velocity Obstacles and Control Barrier Functions}, 
      author={Alejandro Sánchez Roncero and Rafael I. Cabral Muchacho and Petter Ögren},
      year={2024},
      eprint={2409.10117},
      archivePrefix={arXiv},
      primaryClass={cs.RO},
      url={https://arxiv.org/abs/2409.10117}, 
}
