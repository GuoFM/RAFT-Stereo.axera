# RAFT-Stereo 模型转换（AX630C 适配版）

## 概述

本文档描述了将 RAFT-Stereo 模型适配到 AX630C NPU 所需的代码修改。由于 AX630C NPU 对某些操作的限制，需要对原始模型进行以下修改以确保模型能够正确转换和运行。

## 主要修改内容

### 1. 移除 ScatterND 操作

**问题描述：** AX630C NPU 不支持 ScatterND 操作，需要替换为其他实现方式。

**修改位置：** `core/corr.py` 中的相关代码

**修改方案：** 将索引赋值操作改为使用 `torch.cat` 拼接

**原始代码：**
```python
centroid_lvl[...,0] = centroid_lvl[...,0] / 2**i
```

**修改后：**
```python
centroid_lvl = torch.cat([centroid_lvl[..., 0:1] / 2**i, centroid_lvl[..., 1:2]], dim=-1)
```

### 2. upsample_flow 函数维度优化

**问题描述：** AX630C NPU 不支持超过 5 维的张量操作，原始实现使用了 7 维操作。

**修改位置：** `core/raft_stereo.py` 中的 `upsample_flow` 方法

**修改方案：** 将 7 维操作拆分为多个 5 维以内的操作

**原始代码：**
```python
def upsample_flow(self, flow, mask):
    """ Upsample flow field [H/8, W/8, 2] -> [H, W, 2] using convex combination """
    N, D, H, W = flow.shape
    factor = 2 ** self.args.n_downsample
    
    # 原始: 7维操作，NPU不支持
    mask = mask.view(N, 1, 9, factor, factor, H, W)
    up_flow = up_flow.view(N, D, 9, 1, 1, H, W)
    up_flow = torch.sum(mask * up_flow, dim=2)
    # ...
```

**修改后：**
```python
def upsample_flow(self, flow, mask):
    """ Upsample flow field [H/8, W/8, 2] -> [H, W, 2] using convex combination """
    N, D, H, W = flow.shape
    factor = 2 ** self.args.n_downsample
    
    # 修改: 降维到 5 维以内
    mask = mask.view(N, 9, factor * factor, H, W)  # 5维
    mask = torch.softmax(mask, dim=1)
    
    up_flow = F.unfold(factor * flow, [3, 3], padding=1)  # (N, D*9, H*W)
    up_flow = up_flow.view(N, D, 9, H, W)  # 5维
    
    # 5维上做 sum 
    up_flow = (mask.unsqueeze(1) * up_flow.unsqueeze(2)).sum(dim=2)  # (N, D, factor*factor, H, W)
    
    up_flow = up_flow.view(N, D, factor, factor, H, W)
    up_flow = up_flow.permute(0, 1, 4, 2, 5, 3)
    return up_flow.reshape(N, D, factor * H, factor * W)
```

### 3. 修复 ONNX 转换优化问题

**问题描述：** 原始代码在转换为 ONNX 时会被错误优化为 DepthToSpace 操作，导致转换失败。

**修改位置：** `core/raft_stereo.py` 中的 `upsample_flow` 方法末尾

**修改方案：** 添加 `contiguous()` 和 `flatten()` 操作，避免 ONNX 优化器误识别

**原始代码：**
```python
up_flow = up_flow.view(N, D, factor, factor, H, W)
up_flow = up_flow.permute(0, 1, 4, 2, 5, 3)
return up_flow.reshape(N, D, factor * H, factor * W)
```

**修改后：**
```python
up_flow = up_flow.view(N, D, factor, factor, H, W)
up_flow = up_flow.permute(0, 1, 4, 2, 5, 3).contiguous()  
up_flow = up_flow.flatten(2)  
return up_flow.view(N, D, factor * H, factor * W)
```

## 创建环境

```
python3.12 -m venv raft-stereo
source raft-stereo/bin/activate
```

## 安装依赖

```
pip install -r requirements.txt
```

## 导出模型（PyTorch -> ONNX）
本示例基于官方 checkpoint raftstereo-realtime.pth 导出两个版本的模型，一个 `radius`参数值为`1`，一个为`4`。  

### 当 `radius==4`
这个版本以[RAFT-Stereo](https://github.com/princeton-vl/RAFT-Stereo) 官方的 [Faster Implementation](https://github.com/princeton-vl/RAFT-Stereo/tree/main?tab=readme-ov-file#optional-faster-implementation) 为基础，将 `corr_implementation` 参数值 从`reg_cuda`修改为 `alt`  
```
python export_onnx.py --restore_ckpt ../models/raftstereo-realtime.pth \
                --mixed_precision \
                --shared_backbone \
                --n_downsample 3 \
                --n_gru_layers 2 \
                --slow_fast_gru \
                --valid_iters 7 \
                --corr_radius 4 \
                --corr_implementation alt \
                --output_directory ../models \
                --width 1280 \
                --height 384 
```
导出成功会生成文件 `../models/raft_steoro384x1280_r4.onnx`.

### 当 `radius==1`
这个版本以前面的版本为基础，将 `corr_radius` 设置为`1`，损失一些精度，提升速度。
```
python export_onnx.py --restore_ckpt ../models/raftstereo-realtime.pth \
                --mixed_precision \
                --shared_backbone \
                --n_downsample 3 \
                --n_gru_layers 2 \
                --slow_fast_gru \
                --valid_iters 7 \
                --corr_radius 1 \
                --corr_implementation alt \
                --output_directory ../models \
                --width 640 \
                --height 256 
```
导出成功会生成文件 `../models/raft_steoro256x640_r1.onnx`.
  

## 转换模型（ONNX -> Axera）

使用模型转换工具 `Pulsar2` 将 ONNX 模型转换成适用于 Axera 的 NPU 运行的模型文件格式 `.axmodel`，通常情况下需要经过以下两个步骤：

- 生成适用于该模型的 PTQ 量化校准数据集
- 使用 `Pulsar2 build` 命令集进行模型转换（PTQ 量化、编译），更详细的使用说明请参考 [AXera Pulsar2 工具链指导手册](https://pulsar2-docs.readthedocs.io/zh-cn/latest/index.html)

### 下载量化数据集
```
bash download_dataset.sh
```
这个模型的输入是左右目两张图片，比较简单，这里我们直接下载打包好的图片数据  

### 模型转换

#### 修改配置文件
 
检查`config.json` 中 `calibration_dataset` 字段，将该字段配置的路径改为上一步下载的量化数据集存放路径  

#### Pulsar2 build

参考命令如下：


```
pulsar2 build --input ../models/raft_steoro256x640_r4.onnx --config config_r4.json --output_dir build-output-r4 --output_name raft_steoro256x640_r4.axmodel --target_hardware AX620E --compiler.check 0
```
或

```
pulsar2 build --input ../models/raft_steoro256x640_r1.onnx --config config_r1.json --output_dir build-output-r1 --output_name raft_steoro256x640_r1.axmodel --target_hardware AX620E --compiler.check 0
```