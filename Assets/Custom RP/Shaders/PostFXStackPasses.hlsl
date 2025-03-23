#ifndef CUSTOM_POST_FX_PASSES_INCLUDE
#define CUSTOM_POST_FX_PASSES_INCLUDE

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"

TEXTURE2D(_PostFXSource);
TEXTURE2D(_PostFXSource2);
SAMPLER(sampler_linear_clamp);

float4 _PostFXSource_TexelSize;

float4 GetSourceTexelSize () {
    return _PostFXSource_TexelSize;
}

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 screenUV : VAR_SCREEN_UV;
};

Varyings DefaultPassVertex(uint vertexID: SV_VertexID)
{
    Varyings output;
    // (-1, -1) (-1, 3) (3, -1) 
    float outX = vertexID <= 1 ? -1.0 : 3.0f;
    float outY = vertexID == 1 ? 3.0 : -1.0;
    output.positionCS = float4(outX, outY, 0.0, 1.0);
    //(0, 0) (0, 2) (2, 0)
    float outU = vertexID <= 1 ? 0.0 : 2.0;
    float outV = vertexID == 1 ? 2.0 : 0.0;
    output.screenUV = float2(outU, outV);

    if (_ProjectionParams.x < 0.0)
    {
        output.screenUV.y = 1.0 - output.screenUV.y;
    }
    
    return output;
}

float4 GetSource(float2 screenUV)
{
    return SAMPLE_TEXTURE2D_LOD(_PostFXSource, sampler_linear_clamp, screenUV, 0);
}

float4 GetSource2(float2 screenUV) {
    return SAMPLE_TEXTURE2D_LOD(_PostFXSource2, sampler_linear_clamp, screenUV, 0);
}

float4 GetSourceBicubic (float2 screenUV) {
    return SampleTexture2DBicubic(
        TEXTURE2D_ARGS(_PostFXSource, sampler_linear_clamp), screenUV,
        _PostFXSource_TexelSize.zwxy, 1.0, 0.0
    );
}

float4 CopyPassFragment (Varyings input) : SV_TARGET {
    return GetSource(input.screenUV);
}

// enable in high quality
bool _BloomBicubicUpsampling;
float _BloomIntensity;

float4 BloomAddPassFragment (Varyings input) : SV_TARGET {
    float3 lowRes;
    if (_BloomBicubicUpsampling)
    {
        lowRes = GetSourceBicubic(input.screenUV).rgb;
    }
    else
    {
        lowRes = GetSource(input.screenUV).rgb;
    }
    // highRes no upsampling; output size is equal to highRes
    float3 highRes = GetSource2(input.screenUV).rgb;
    return float4(_BloomIntensity * lowRes + highRes, 1.0);
}

float4 BloomHorizontalPassFragment (Varyings input) : SV_TARGET {
    float3 color = 0.0;
    float offsets[] = {-4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0};
    float weights[] = {
        0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703,
        0.19459459, 0.12162162, 0.05405405, 0.01621622
    };
    for (int i = 0; i < 9; i++)
    {
        // We'll also downsample at the same time so each
        // offset step is double the source texel width. 
        float offset = offsets[i] * 2.0 * GetSourceTexelSize().x;
        color += GetSource(input.screenUV + float2(offset, 0.0)).rgb * weights[i];
    }
    return float4(color, 1.0);
}

float4 BloomVerticalPassFragment (Varyings input) : SV_TARGET {
    float3 color = 0.0;
    /*
     *  original offsets and weights is as follows. we used bilinear filter to reduce sample number.
        float offsets[] = {-4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0};
        float weights[] = {
            0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703,
            0.19459459, 0.12162162, 0.05405405, 0.01621622
        };
     */
    float offsets[] = {-3.23076923, -1.38461538, 0.0, 1.38461538, 3.23076923};
    float weights[] = {0.07027027, 0.31621622, 0.22702703, 0.31621622, 0.07027027};
    
    for (int i = 0; i < 5; i++)
    {
        // Should not multiply 2 at this time. 
        float offset = offsets[i] * GetSourceTexelSize().y;
        color += GetSource(input.screenUV + float2(0.0, offset)).rgb * weights[i];
    }
    return float4(color, 1.0);
}

float4 _BloomThreshold;

float3 ApplyBloomThreshold (float3 color)
{
    float brightness = Max3(color.r, color.g, color.b);
    // \min\left(\max\left(0,b-t+tk\right),2tk\right)
    // max{0, x} means clamp the minimum to 0 
    float soft = brightness + _BloomThreshold.y;
    soft = clamp(soft, 0.0, _BloomThreshold.z);
    // cal s
    soft = soft * soft * _BloomThreshold.w;

    float contribution = max(soft, brightness - _BloomThreshold.x);
    contribution /= max(brightness, 0.00001);
    return color * contribution;
}

float4 BloomPrefilterPassFragment (Varyings input) : SV_TARGET {
    float3 color = ApplyBloomThreshold(GetSource(input.screenUV).rgb);
    return float4(color, 1.0);
}

float4 BloomPrefilterFirefliesPassFragment (Varyings input) : SV_TARGET {
    float3 color = 0.0;
    float weightSum = 0.0;
    float2 offsets[] = {
        float2(0.0, 0.0),
        float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0),
    };
    for (int i = 0; i < 5; i++) {
        float3 c =
            GetSource(input.screenUV + offsets[i] * GetSourceTexelSize().xy * 2.0).rgb;
        c = ApplyBloomThreshold(c);
        float w = 1.0 / (Luminance(c) + 1.0);
        color += c * w;
        weightSum += w;
    }
    color *= 1.0 / weightSum;
    return float4(color, 1.0);
}

float4 BloomScatterPassFragment (Varyings input) : SV_TARGET {
    float3 lowRes;
    if (_BloomBicubicUpsampling)
    {
        lowRes = GetSourceBicubic(input.screenUV).rgb;
    }
    else
    {
        lowRes = GetSource(input.screenUV).rgb;
    }
    
    float3 highRes = GetSource2(input.screenUV).rgb;
    return float4(lerp(highRes, lowRes, _BloomIntensity), 1);
}

float4 BloomScatterFinalPassFragment (Varyings input) : SV_TARGET {
    float3 lowRes;
    if (_BloomBicubicUpsampling)
    {
        lowRes = GetSourceBicubic(input.screenUV).rgb;
    }
    else
    {
        lowRes = GetSource(input.screenUV).rgb;
    }
    
    float3 highRes = GetSource2(input.screenUV).rgb;
    lowRes += highRes - ApplyBloomThreshold(highRes);
    return float4(lerp(highRes, lowRes, _BloomIntensity), 1);
}

float4 _ColorAdjustments;
float4 _ColorFilter;
float4 _WhiteBalance;
float4 _SplitToningShadows, _SplitToningHighlights;
float4 _ChannelMixerRed, _ChannelMixerGreen, _ChannelMixerBlue;
float4 _SMHShadows, _SMHMidtones, _SMHHighlights, _SMHRange;

float Luminance (float3 color, bool useACES) {
    return useACES ? AcesLuminance(color) : Luminance(color);
}

float3 ColorGradePostExposure (float3 color) {
    // _ColorAdjustments.x is 2^{exposure}
    return color * _ColorAdjustments.x;
}

float3 ColorGradingContrast (float3 color, bool useACES) {
    color = useACES ? ACES_to_ACEScc(unity_to_ACES(color)) : LinearToLogC(color);
    color = (color - ACEScc_MIDGRAY) * _ColorAdjustments.y + ACEScc_MIDGRAY;
    return useACES ? ACES_to_ACEScg(ACEScc_to_ACES(color)) : LogCToLinear(color);
}

float3 ColorGradeColorFilter (float3 color) {
    return color * _ColorFilter.rgb;
}

float3 ColorGradingHueShift (float3 color) {
    color = RgbToHsv(color);
    float hue = color.x + _ColorAdjustments.z;
    // Because hue is defined on a 0–1 color wheel
    // we have to wrap it around if it goes out of range.
    // We can use RotateHue for that, passing it the adjusted hue, 0, and 1 as arguments
    color.x = RotateHue(hue, 0.0, 1.0);
    return HsvToRgb(color);
}

float3 ColorGradingSaturation (float3 color, bool useACES) {
    float luminance = Luminance(color, useACES);
    return (color - luminance) * _ColorAdjustments.w + luminance;
}

float3 ColorGradeWhiteBalance (float3 color) {
    color = LinearToLMS(color);
    color *= _WhiteBalance.rgb;
    return LMSToLinear(color);
}

float3 ColorGradeSplitToning (float3 color, bool useACES) {
    color = PositivePow(color, 1.0 / 2.2);
    float t = saturate(Luminance(saturate(color), useACES) + _SplitToningShadows.w);
    float3 shadows = lerp(0.5, _SplitToningShadows.rgb, 1.0 - t);
    float3 highlights = lerp(0.5, _SplitToningHighlights.rgb, t);
    color = SoftLight(color, shadows);
    color = SoftLight(color, highlights);
    return PositivePow(color, 2.2);
}

float3 ColorGradingChannelMixer (float3 color) {
    return mul(
        float3x3(_ChannelMixerRed.rgb, _ChannelMixerGreen.rgb, _ChannelMixerBlue.rgb),
        color
    );
}

float3 ColorGradingShadowsMidtonesHighlights (float3 color, bool useACES) {
    float luminance = Luminance(color, useACES);
    float shadowsWeight = 1.0 - smoothstep(_SMHRange.x, _SMHRange.y, luminance);
    float highlightsWeight = smoothstep(_SMHRange.z, _SMHRange.w, luminance);
    float midtonesWeight = 1.0 - shadowsWeight - highlightsWeight;
    return
        color * _SMHShadows.rgb * shadowsWeight +
        color * _SMHMidtones.rgb * midtonesWeight +
        color * _SMHHighlights.rgb * highlightsWeight;
}

float3 ColorGrade (float3 color, bool useACES = false) {
    // This works, but could go wrong for very large values due to precision limitations.
    // For the same reason very large values end up at 1 much earlier than infinity.
    // So let's clamp the color before performing tone mapping.
    // A limit of 60 avoids any potential issues for all modes that we will support.
    // 
    // color = min(color, 60.0);
    // Because we're no longer relying on the rendered image
    // we no longer need to limit the range to 60. It's already limited by the range of the LUT.
    color = ColorGradePostExposure(color);
    color = ColorGradeWhiteBalance(color);
    color = ColorGradingContrast(color, useACES);
    color = ColorGradeColorFilter(color);
    color = max(color, 0.0);
    color = ColorGradeSplitToning(color, useACES);
    color = ColorGradingChannelMixer(color);
    color = max(color, 0.0);
    color = ColorGradingShadowsMidtonesHighlights(color, useACES);
    color = ColorGradingHueShift(color);
    color = ColorGradingSaturation(color, useACES);
    return max(useACES ? ACEScg_to_ACES(color) : color, 0.0);
}

float4 _ColorGradingLUTParameters;
bool _ColorGradingLUTInLogC;

TEXTURE2D(_ColorGradingLUT);

float3 ApplyColorGradingLUT (float3 color) {
    return ApplyLut2D(
        TEXTURE2D_ARGS(_ColorGradingLUT, sampler_linear_clamp),
        saturate(_ColorGradingLUTInLogC ? LinearToLogC(color) : color),
        _ColorGradingLUTParameters.xyz
    );
}

float4 FinalPassFragment (Varyings input) : SV_TARGET {
    float4 color = GetSource(input.screenUV);
    color.rgb = ApplyColorGradingLUT(color.rgb);
    return color;
}

float3 GetColorGradedLUT (float2 uv, bool useACES = false) {
    float3 color = GetLutStripValue(uv, _ColorGradingLUTParameters);
    //The LUT matrix that we get is in linear color space and only covers the 0–1 range.
    //To support HDR we have to extend this range.
    //We can do this by interpreting the input color as being in Log C space.
    //That extends the range to just below 59.
    //
    // return ColorGrade(color, useACES); should be change to LogCToLinear(color)
    // but only in HDR mode we need value over 1.
    return ColorGrade(_ColorGradingLUTInLogC ? LogCToLinear(color) : color, useACES);
}

float4 ColorGradingNonePassFragment (Varyings input) : SV_TARGET {
    float3 color = GetColorGradedLUT(input.screenUV);
    return float4(color, 1.0);
}

float4 ColorGradingACESPassFragment (Varyings input) : SV_TARGET {
    float3 color = GetColorGradedLUT(input.screenUV, true);
    color = AcesTonemap(color);
    return float4(color, 1.0);
}

float4 ColorGradingNeutralPassFragment (Varyings input) : SV_TARGET {
    float3 color = GetColorGradedLUT(input.screenUV);
    color = NeutralTonemap(color);
    return float4(color, 1.0);
}

float4 ColorGradingReinhardPassFragment (Varyings input) : SV_TARGET {
    float3 color = GetColorGradedLUT(input.screenUV);
    color /= color + 1.0;
    return float4(color, 1.0);
}
#endif