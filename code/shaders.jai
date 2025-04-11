// TODO(Sleepster):
//VALUE :: #insert -> string END
//#import "some shader file";
//END

BASIC_SHADER_SOURCE_TEXT :: #string END 

#ifdef VERTEX_SHADER
layout(location = 0) in vec4 vPosition;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec2 vUVData;

out vec4 vOutColor;
out vec2 vOutUVData;

void main()
{
    vOutColor  = vColor;
    vOutUVData = vUVData;

    gl_Position = vPosition;
}
#endif

#ifdef FRAGMENT_SHADER
layout(location = 0) in vec4 vOutColor;
layout(location = 1) in vec2 vOutUVData;

out vec4 vFragColor;
layout(binding = 0) uniform sampler2D GameAtlas;

void main()
{
    vec4 TextureColor = texelFetch(GameAtlas, ivec2(vOutUVData), 0);
    vFragColor = TextureColor * vOutColor;
}
#endif

END

FONT_SHADER_SOURCE_TEXT :: #string END

#ifdef VERTEX_SHADER
layout(location = 0) in vec4 vPosition;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec2 vUVData;

out vec4 vOutColor;
out vec2 vOutUVData;

void main()
{
    vOutColor  = vColor;
    vOutUVData = vUVData;

    gl_Position = vPosition;
}
#endif

#ifdef FRAGMENT_SHADER
layout(location = 0) in vec4 vOutColor;
layout(location = 1) in vec2 vOutUVData;

layout(binding  = 0) uniform sampler2D FontAtlas;

out vec4 vFragColor;
void main()
{
    vec2 normalizedUV = vOutUVData / vec2(2048, 2048);
    vec4 TextureColor = texture(FontAtlas, normalizedUV);
    if(TextureColor.a < 0.3)
    {
        discard;
    }

    vFragColor  = vec4(vOutColor.rgb, TextureColor.a * vOutColor.a);
}
#endif

END

NEW_BASIC_SHADER_TEXT :: #string END

#ifdef VERTEX_SHADER
layout(location = 0) in vec4 vPosition;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec2 vUVData;
layout(location = 3) in uint vTexIndex;

out vec4      vOutColor;
out vec2      vOutUVData;
out flat uint vOutTexIndex;

void main()
{
    vOutColor       = vColor;
    vOutUVData      = vUVData;
    vOutTexIndex    = vTexIndex;

    gl_Position = vPosition;
}
#endif

#ifdef FRAGMENT_SHADER
layout(location = 0) in vec4 vOutColor;
layout(location = 1) in vec2 vOutUVData;
layout(location = 2) in flat uint vOutTexIndex;

uniform sampler2D AtlasArray[32];

out vec4 vFragColor;
void main()
{
    vec2 NormalizedUV = vOutUVData / ivec2(2048, 2048);
    vec4 TextureColor = texture(AtlasArray[vOutTexIndex], NormalizedUV);
    if(TextureColor.a == 0.0)
    {
        discard;
    }

    vFragColor = TextureColor * vOutColor;
}
#endif

END
