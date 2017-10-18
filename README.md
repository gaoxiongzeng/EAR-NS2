# EAR-NS2
NS2 code for EAR in APNet'17.

## Software requirements
To reproduce NS2 simulation results of [EAR paper](https://dl.acm.org/citation.cfm?id=3107002) in APNet'17, you need following softwares:
  - [Network Simulator (NS) 2.35](https://sourceforge.net/projects/nsnam/)

## Installation
Download [Network Simulator (NS) 2.35](https://sourceforge.net/projects/nsnam/) and unzip it.
```
$ tar -zxvf ns-allinone-2.35.tar.gz
```
  
Copy all from [ear-ns2](https://github.com/gaoxiongzeng/EAR-NS2/ear-ns2/) into ```ns-allinone-2.35/ns-2.35```.

Add ```queue/priority.o \``` to ```ns-allinone-2.35/ns-2.35/Makefile.in```.

Remove bugs of ns-allinone-2.35: In linkstate/ls.h:137:58, use ‘this->erase’ instead.

Install NS2.
```
$ cd ns-allinone-2.35
$ ./install
```

## Simulation, Workload and Data Processing Scripts
Simulation scripts are contained in scripts/ folder. It runs in a simple testing scenario: EAR protocol with the web search workload under a 3-level fattree. Two publicly available workloads are also added in scripts/cdf/ folder.

Run basic simulation.
```
$ ns scripts/fattree_empirical.tcl
```

The simple testing simulation finishes in ~5 minutes. track.tr and flow.tr are generated as the results.

For data processing, you can use result.py to parse flow.tr file as follows:
```
$ python result.py flow.tr
```

## Contact
If you have any question about EAR simulation code, please contact [Gaoxiong Zeng](http://gaoxiongzeng.github.io/).

## Acknowledgement
Thank [Wei Bai](http://baiwei0427.github.io/) for sharing [MQ-ECN simulation code](https://github.com/HKUST-SING/MQ-ECN-NS2/).  
