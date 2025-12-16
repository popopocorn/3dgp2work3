#include "Light.hlsl"
cbuffer cbCameraInfo : register(b1)
{
	matrix					gmtxView : packoffset(c0);
	matrix					gmtxProjection : packoffset(c4);
	float3					gvCameraPosition : packoffset(c8);
};

cbuffer cbGameObjectInfo : register(b2)
{
	matrix					gmtxGameObject : packoffset(c0);
	MATERIAL				gMaterial : packoffset(c4);
	uint					gnTexturesMask : packoffset(c8);
};



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//#define _WITH_VERTEX_LIGHTING

#define MATERIAL_ALBEDO_MAP			0x01
#define MATERIAL_SPECULAR_MAP		0x02
#define MATERIAL_NORMAL_MAP			0x04
#define MATERIAL_METALLIC_MAP		0x08
#define MATERIAL_EMISSION_MAP		0x10
#define MATERIAL_DETAIL_ALBEDO_MAP	0x20
#define MATERIAL_DETAIL_NORMAL_MAP	0x40

Texture2D gtxtAlbedoTexture : register(t6);
Texture2D gtxtSpecularTexture : register(t7);
Texture2D gtxtNormalTexture : register(t8);
Texture2D gtxtMetallicTexture : register(t9);
Texture2D gtxtEmissionTexture : register(t10);
Texture2D gtxtDetailAlbedoTexture : register(t11);
Texture2D gtxtDetailNormalTexture : register(t12);

SamplerState gssWrap : register(s0);

struct VS_STANDARD_INPUT
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	float3 bitangent : BITANGENT;
};

struct VS_STANDARD_OUTPUT
{
	float4 position : SV_POSITION;
	float3 positionW : POSITION;
	float3 normalW : NORMAL;
	float3 tangentW : TANGENT;
	float3 bitangentW : BITANGENT;
	float2 uv : TEXCOORD;
    float4 positionLight : POSITION1;
};

Texture2D<float> gtxtShadowMap : register(t17);
SamplerComparisonState gShadowSampler : register(s2);

cbuffer cbLightCamera : register(b5)
{
    float4x4 gLightViewProj;
}

VS_STANDARD_OUTPUT VSStandard(VS_STANDARD_INPUT input)
{
    VS_STANDARD_OUTPUT output;

    output.positionW = (float3) mul(float4(input.position, 1.0f), gmtxGameObject);
    output.normalW = mul(input.normal, (float3x3) gmtxGameObject);
    output.tangentW = (float3) mul(float4(input.tangent, 1.0f), gmtxGameObject);
    output.bitangentW = (float3) mul(float4(input.bitangent, 1.0f), gmtxGameObject);
    output.position = mul(mul(float4(output.positionW, 1.0f), gmtxView), gmtxProjection);
    output.uv = input.uv;

    // Light space position 추가
    output.positionLight = mul(float4(output.positionW, 1.0f), gLightViewProj);

    return output;
}

// Shadow 계산 함수
float CalcShadow(float4 positionLight)
{
    // NDC 공간으로 변환
    float3 proj = positionLight.xyz / positionLight.w;

    // UV 변환 (Y 반전)
    float2 shadowUV;
    shadowUV.x = proj.x * 0.5f + 0.5f;
    shadowUV.y = 1.0f - (proj.y * 0.5f + 0.5f); // <- Y 반전

    float shadowDepth = proj.z;

    // 프러스터 범위 밖이면 그림자 없음
    if (shadowUV.x < 0.0f || shadowUV.x > 1.0f ||
        shadowUV.y < 0.0f || shadowUV.y > 1.0f ||
        shadowDepth < 0.0f || shadowDepth > 1.0f)
        return 1.0f;

    // Shader bias 적용
    float bias = 0.0015f;

    // SampleCmpLevelZero 사용: 그림자 깊이 비교 (shadowDepth - bias)
    float shadow = gtxtShadowMap.SampleCmpLevelZero(gShadowSampler, shadowUV, shadowDepth - bias);

    return shadow;
}




float4 PSStandard(VS_STANDARD_OUTPUT input) : SV_TARGET
{
    float4 cAlbedoColor = float4(0, 0, 0, 1);
    float4 cSpecularColor = float4(0, 0, 0, 1);
    float4 cNormalColor = float4(0, 0, 0, 1);
    float4 cMetallicColor = float4(0, 0, 0, 1);
    float4 cEmissionColor = float4(0, 0, 0, 1);

    if (gnTexturesMask & MATERIAL_ALBEDO_MAP)
        cAlbedoColor = gtxtAlbedoTexture.Sample(gssWrap, input.uv);
    if (gnTexturesMask & MATERIAL_SPECULAR_MAP)
        cSpecularColor = gtxtSpecularTexture.Sample(gssWrap, input.uv);
    if (gnTexturesMask & MATERIAL_NORMAL_MAP)
        cNormalColor = gtxtNormalTexture.Sample(gssWrap, input.uv);
    if (gnTexturesMask & MATERIAL_METALLIC_MAP)
        cMetallicColor = gtxtMetallicTexture.Sample(gssWrap, input.uv);
    if (gnTexturesMask & MATERIAL_EMISSION_MAP)
        cEmissionColor = gtxtEmissionTexture.Sample(gssWrap, input.uv);

    float4 cColor = cAlbedoColor + cSpecularColor + cEmissionColor;

    float3 normalW = input.normalW;
    if (gnTexturesMask & MATERIAL_NORMAL_MAP)
    {
        float3x3 TBN = float3x3(normalize(input.tangentW), normalize(input.bitangentW), normalize(input.normalW));
        float3 vNormal = normalize(cNormalColor.rgb * 2.0f - 1.0f); // [0,1] -> [-1,1]
        normalW = normalize(mul(vNormal, TBN));
    }

    float shadow = CalcShadow(input.positionLight);
    
    float4 lighting = Lighting(input.positionW, normalW, gvCameraPosition, gMaterial);

    // 그림자 계산
    

    // 최종 색상에 그림자 적용
    float4 finalColor = cAlbedoColor * lighting;
    finalColor.rgb *= shadow;

    return finalColor;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
struct VS_SKYBOX_CUBEMAP_INPUT
{
	float3 position : POSITION;
};

struct VS_SKYBOX_CUBEMAP_OUTPUT
{
	float3	positionL : POSITION;
	float4	position : SV_POSITION;
};

VS_SKYBOX_CUBEMAP_OUTPUT VSSkyBox(VS_SKYBOX_CUBEMAP_INPUT input)
{
	VS_SKYBOX_CUBEMAP_OUTPUT output;

	output.position = mul(mul(mul(float4(input.position, 1.0f), gmtxGameObject), gmtxView), gmtxProjection);
	output.positionL = input.position;

	return(output);
}

TextureCube gtxtSkyCubeTexture : register(t13);
SamplerState gssClamp : register(s1);

float4 PSSkyBox(VS_SKYBOX_CUBEMAP_OUTPUT input) : SV_TARGET
{
	float4 cColor = gtxtSkyCubeTexture.Sample(gssClamp, input.positionL);

	return(cColor);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
struct VS_SPRITE_TEXTURED_INPUT
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_SPRITE_TEXTURED_OUTPUT
{
	float4 position : SV_POSITION;
	float2 uv : TEXCOORD;
};

VS_SPRITE_TEXTURED_OUTPUT VSTextured(VS_SPRITE_TEXTURED_INPUT input)
{
	VS_SPRITE_TEXTURED_OUTPUT output;

	output.position = mul(mul(mul(float4(input.position, 1.0f), gmtxGameObject), gmtxView), gmtxProjection);
	output.uv = input.uv;

	return(output);
}

/*
float4 PSTextured(VS_SPRITE_TEXTURED_OUTPUT input, uint nPrimitiveID : SV_PrimitiveID) : SV_TARGET
{
	float4 cColor;
	if (nPrimitiveID < 2)
		cColor = gtxtTextures[0].Sample(gWrapSamplerState, input.uv);
	else if (nPrimitiveID < 4)
		cColor = gtxtTextures[1].Sample(gWrapSamplerState, input.uv);
	else if (nPrimitiveID < 6)
		cColor = gtxtTextures[2].Sample(gWrapSamplerState, input.uv);
	else if (nPrimitiveID < 8)
		cColor = gtxtTextures[3].Sample(gWrapSamplerState, input.uv);
	else if (nPrimitiveID < 10)
		cColor = gtxtTextures[4].Sample(gWrapSamplerState, input.uv);
	else
		cColor = gtxtTextures[5].Sample(gWrapSamplerState, input.uv);
	float4 cColor = gtxtTextures[NonUniformResourceIndex(nPrimitiveID/2)].Sample(gWrapSamplerState, input.uv);

	return(cColor);
}
*/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
Texture2D gtxtTerrainTexture : register(t14);
Texture2D gtxtDetailTexture : register(t15);
Texture2D gtxtAlphaTexture : register(t16);

float4 PSTextured(VS_SPRITE_TEXTURED_OUTPUT input) : SV_TARGET
{
	float4 cColor = gtxtTerrainTexture.Sample(gssWrap, input.uv);

	return(cColor);
}
struct VS_TERRAIN_INPUT
{
    float3 position : POSITION;
    float4 color : COLOR;
    float2 uv0 : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
};

struct VS_TERRAIN_OUTPUT
{
    float4 position : SV_POSITION;
    float4 color : COLOR;
    float2 uv0 : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
    float3 positionW : TEXCOORD2; // World Position
    float4 positionLight : TEXCOORD3; // Light ViewProj Position
};

VS_TERRAIN_OUTPUT VSTerrain(VS_TERRAIN_INPUT input)
{
    VS_TERRAIN_OUTPUT output;

    float4 worldPos = mul(float4(input.position, 1.0f), gmtxGameObject);

    output.positionW = worldPos.xyz;
    output.position = mul(mul(worldPos, gmtxView), gmtxProjection);
    output.color = input.color;
    output.uv0 = input.uv0;
    output.uv1 = input.uv1;

    // LightViewProj 적용
    output.positionLight = mul(worldPos, gLightViewProj);

    return output;
}


float4 PSTerrain(VS_TERRAIN_OUTPUT input) : SV_TARGET
{
    float4 cBaseTexColor = gtxtTerrainTexture.Sample(gssWrap, input.uv0);
    float4 cDetailTexColor = gtxtDetailTexture.Sample(gssWrap, input.uv1);

    float4 cColor = cBaseTexColor * 0.5f + cDetailTexColor * 0.5f;

    // LightViewProj 기반 그림자 적용
    float shadow = CalcShadow(input.positionLight);
    cColor.rgb *= shadow;

    return cColor;
}



/////////////////////////////////////////////////////////////
VS_STANDARD_OUTPUT VSUI(VS_STANDARD_INPUT input)
{
    VS_STANDARD_OUTPUT output;

    output.positionW = (float3) mul(float4(input.position, 1.0f), gmtxGameObject);
	
    output.position = float4(output.positionW, 1.0f);
    output.uv = input.uv;

    return (output);
}

float4 PSUI(VS_STANDARD_OUTPUT input) : SV_TARGET
{
    float4 cAlbedoColor = float4(0.0f, 0.0f, 0.0f, 1.0f);


    if (gnTexturesMask & MATERIAL_ALBEDO_MAP)
        cAlbedoColor = gtxtAlbedoTexture.Sample(gssWrap, input.uv);

    float4 cColor = cAlbedoColor;

    return (cColor);
}


struct VS_TEXTURED_OUTPUT
{
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
};

// 풀스크린 버텍스 셰이더, 우하단 1/4
VS_TEXTURED_OUTPUT VSTextureToScreen(uint nVertexID : SV_VertexID)
{
    VS_TEXTURED_OUTPUT output;

    float x0 = 0.5f; // 우하단 시작 x
    float y0 = -1.0f; // 우하단 시작 y
    float x1 = 1.0f; // 우하단 끝 x
    float y1 = -0.5f; // 우하단 끝 y

    if (nVertexID == 0)
    {
        output.position = float4(x0, y1, 0, 1);
        output.uv = float2(0, 0);
    }
    if (nVertexID == 1)
    {
        output.position = float4(x1, y1, 0, 1);
        output.uv = float2(1, 0);
    }
    if (nVertexID == 2)
    {
        output.position = float4(x1, y0, 0, 1);
        output.uv = float2(1, 1);
    }
    if (nVertexID == 3)
    {
        output.position = float4(x0, y1, 0, 1);
        output.uv = float2(0, 0);
    }
    if (nVertexID == 4)
    {
        output.position = float4(x1, y0, 0, 1);
        output.uv = float2(1, 1);
    }
    if (nVertexID == 5)
    {
        output.position = float4(x0, y0, 0, 1);
        output.uv = float2(0, 1);
    }

    return output;
}
float4 PSTextureToScreen(VS_TEXTURED_OUTPUT input) : SV_TARGET
{
    // mip level 0 사용
    float depth = gtxtShadowMap.Sample(gssWrap, input.uv);
    return float4(depth, depth, depth, 1.0f);
}