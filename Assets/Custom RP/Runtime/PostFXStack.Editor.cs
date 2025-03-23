using UnityEditor;
using UnityEngine;

partial class PostFXStack
{
    partial void ApplySceneViewState();
#if UNITY_EDITOR
    // Update is called once per frame
    partial void ApplySceneViewState()
    {
        if (camera.cameraType == CameraType.SceneView &&
            !SceneView.currentDrawingSceneView.sceneViewState.showImageEffects)
        {
            settings = null;
        }
    }
#endif
}
