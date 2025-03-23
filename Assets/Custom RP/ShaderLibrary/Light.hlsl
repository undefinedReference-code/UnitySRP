#ifndef CUSTOM_LIGHT_INCLUDED
#define CUSTOM_LIGHT_INCLUDED

#define MAX_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_OTHER_LIGHT_COUNT 64

CBUFFER_START(_CustomLight)
	int _DirectionalLightCount;
	float4 _DirectionalLightColors[MAX_DIRECTIONAL_LIGHT_COUNT];
	float4 _DirectionalLightDirections[MAX_DIRECTIONAL_LIGHT_COUNT];
	float4 _DirectionalLightShadowData[MAX_DIRECTIONAL_LIGHT_COUNT];

	int _OtherLightCount;
	float4 _OtherLightColors[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightPositions[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightDirections[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightSpotAngles[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightShadowData[MAX_OTHER_LIGHT_COUNT];
CBUFFER_END

struct Light {
	float3 color;
	float3 direction;
	float attenuation;
};

int GetDirectionalLightCount () {
	return _DirectionalLightCount;
}

int GetOtherLightCount () {
	return _OtherLightCount;
}

DirectionalShadowData GetDirectionalShadowData (int lightIndex, ShadowData shadowData) {
	DirectionalShadowData data;
	data.strength = _DirectionalLightShadowData[lightIndex].x;
	// tile in shadow map to get.
	data.tileIndex = _DirectionalLightShadowData[lightIndex].y + shadowData.cascadeIndex;
	data.normalBias = _DirectionalLightShadowData[lightIndex].z;
	data.shadowMaskChannel = _DirectionalLightShadowData[lightIndex].w;
	return data;
}

OtherShadowData GetOtherShadowData (int lightIndex) {
	OtherShadowData data;
	data.strength = _OtherLightShadowData[lightIndex].x;
	data.tileIndex = _OtherLightShadowData[lightIndex].y;
	data.isPoint = _OtherLightShadowData[lightIndex].z == 1;
	data.shadowMaskChannel = _OtherLightShadowData[lightIndex].w;
	
	// GetOtherShadowData only has shadow data, but the following comes from light data.
	// Give Default value here.
	data.lightPositionWS = 0.0f;
	data.spotDirectionWS = 0.0f;
	data.lightDirectionWS = 0.0f;
	return data;
}


Light GetDirectionalLight (int index, Surface surfaceWS, ShadowData shadowData) {
	Light light;
	light.color = _DirectionalLightColors[index].rgb;
	light.direction = _DirectionalLightDirections[index].xyz;
	DirectionalShadowData dirShadowData = GetDirectionalShadowData(index,shadowData);
	light.attenuation =  GetDirectionalShadowAttenuation(dirShadowData, shadowData, surfaceWS);
	return light;
}

// light is an abstraction from real light(point, directional,...) to shading
// in pbr, we don't care light position, we only need color, dir and attenuation
Light GetOtherLight (int index, Surface surfaceWS, ShadowData shadowData) {
	Light light;
	light.color = _OtherLightColors[index].rgb;
	// position of spot light
	float3 position = _OtherLightPositions[index].xyz;

	// light.diraction is from object to light pos
	float3 ray = position - surfaceWS.position;
	light.direction = normalize(ray);
	
	float distanceSqr = max(dot(ray, ray), 0.00001);
	float rangeAttenuation = Square(
		saturate(1.0 - Square(distanceSqr * _OtherLightPositions[index].w))
	);
	// this is for spot light
	// a = \frac{1}{cos(\frac{r_i}{2})-cos(\frac{r_o}{2})}
	// b = -cos(\frac{r_o}{2}) a
	// result = saturate(da+b)^2
	// in point light, a = 0, b = 1
	float4 spotAngles = _OtherLightSpotAngles[index];
	float3 spotDirection = _OtherLightDirections[index].xyz;
	// spot Direction is the negative of spot light's local forward.
	float d = dot(spotDirection, light.direction);
	float spotAttenuation = Square(saturate(d * spotAngles.x + spotAngles.y));
	
	//rangeAttenuation / distanceSqr is rangeAttenuation * 1 / distanceSqr
	light.attenuation = spotAttenuation * rangeAttenuation / distanceSqr;

	OtherShadowData otherShadowData = GetOtherShadowData(index);

	otherShadowData.lightPositionWS = position;
	otherShadowData.spotDirectionWS = spotDirection;
	otherShadowData.lightDirectionWS = light.direction;
	
	light.attenuation *= GetOtherShadowAttenuation(otherShadowData, shadowData, surfaceWS);
	return light;
}

#endif