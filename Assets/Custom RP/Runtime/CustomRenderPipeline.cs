using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public partial  class CustomRenderPipeline : RenderPipeline 
{
    CameraRenderer renderer = new CameraRenderer();
    bool useDynamicBatching;
    bool useGPUInstancing;
    bool useLightsPerObject;
    ShadowSettings shadowSettings;
    PostFXSettings postFXSettings;
    bool allowHDR;
    int colorLUTResolution;

    public CustomRenderPipeline(bool allowHDR, bool useDynamicBatching, bool useGPUInstancing, 
        bool useSRPBatcher, bool useLightsPerObject, ShadowSettings shadowSettings,
        PostFXSettings postFXSettings, int colorLUTResolution)
    {
        this.allowHDR = allowHDR;
        this.useDynamicBatching = useDynamicBatching;
        this.useGPUInstancing = useGPUInstancing;
        this.useLightsPerObject = useLightsPerObject;
        GraphicsSettings.useScriptableRenderPipelineBatching = useSRPBatcher;
        GraphicsSettings.lightsUseLinearIntensity = true;
        this.shadowSettings = shadowSettings;
        this.postFXSettings = postFXSettings;
        this.colorLUTResolution = colorLUTResolution;
        InitializeForEditor();
    }
    protected override void Render(ScriptableRenderContext context, Camera[] cameras)
    { 
        
    }

    protected override void Render(ScriptableRenderContext context, List<Camera> cameras)
    {
        for (int i = 0; i < cameras.Count; i++)
        {
            renderer.Render(context, cameras[i], allowHDR, useDynamicBatching, 
                useGPUInstancing, useLightsPerObject, shadowSettings,
                postFXSettings, colorLUTResolution);
        }
    }


}