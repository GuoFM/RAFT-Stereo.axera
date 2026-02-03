/*
 * AXERA is pleased to support the open source community by making ax-samples available.
 * 
 * Copyright (c) 2022, AXERA Semiconductor (Shanghai) Co., Ltd. All rights reserved.
 * 
 * Licensed under the BSD 3-Clause License (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 * 
 * https://opensource.org/licenses/BSD-3-Clause
 * 
 * Unless required by applicable law or agreed to in writing, software distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

#pragma once

#include <cstdint>
#include <opencv2/opencv.hpp>
#include <vector>
#include <algorithm>
#include <cmath>
#include <string>
#include <sstream>
#include <array>

namespace common
{
    // Resize without letterbox (direct resize)
    void get_input_data_no_letterbox(const cv::Mat& mat, std::vector<uint8_t>& image, int model_h, int model_w, bool bgr2rgb = false)
    {
        cv::Mat img_new(model_h, model_w, CV_8UC3, image.data());
        cv::resize(mat, img_new, cv::Size(model_w, model_h));
        if (bgr2rgb)
        {
            cv::cvtColor(img_new, img_new, cv::COLOR_BGR2RGB);
        }
    }

    // Read file to vector
    bool read_file(const char* fn, std::vector<uchar>& data)
    {
        FILE* fp = fopen(fn, "r");
        if (fp != nullptr)
        {
            fseek(fp, 0L, SEEK_END);
            auto len = ftell(fp);
            fseek(fp, 0, SEEK_SET);
            data.clear();
            size_t read_size = 0;
            if (len > 0)
            {
                data.resize(len);
                read_size = fread(data.data(), 1, len, fp);
            }
            fclose(fp);
            return read_size == (size_t)len;
        }
        return false;
    }
} // namespace common

namespace utilities
{
    // Parse comma-separated string to array
    template<size_t N>
    bool parse_string(const std::string& input, std::array<int, N>& output)
    {
        std::stringstream ss(input);
        std::string item;
        size_t idx = 0;
        
        while (std::getline(ss, item, ',') && idx < N)
        {
            try
            {
                output[idx++] = std::stoi(item);
            }
            catch (...)
            {
                return false;
            }
        }
        
        return idx == N;
    }
} // namespace utilities
