package backend;

import flixel.FlxG;
import openfl.display.BitmapData;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.Texture;

#if mobile
import lime.utils.UInt8Array;
#end

/**
 * Handler for loading and managing ASTC compressed textures in mods.
 * ASTC (Adaptive Scalable Texture Compression) provides high compression ratios
 * with good quality, ideal for mobile devices.
 */
class ASTCTextureHandler
{
	// Map to store ASTC compressed texture data
	static var astcData:Map<String, ASTCTextureInfo> = new Map();

	/**
	 * Load an ASTC texture from a file path
	 * @param file Path to the .astc file
	 * @return FlxGraphic with the compressed texture, or null if failed
	 */
	public static function loadTexture(file:String):FlxGraphic
	{
		#if mobile
		if (!sys.FileSystem.exists(file)) return null;

		var bytes = sys.io.File.getBytes(file);
		if (bytes.length < 16) return null;

		// Check ASTC magic number: 0x5CA1AB13
		if (bytes.get(0) != 0x13 || bytes.get(1) != 0xAB || 
			bytes.get(2) != 0xA1 || bytes.get(3) != 0x5C)
		{
			trace('[ASTC] Invalid file format: $file');
			return null;
		}

		var blockX = bytes.get(4);
		var blockY = bytes.get(5);

		// Parse dimensions (24-bit little endian)
		var width = bytes.get(7) | (bytes.get(8) << 8) | (bytes.get(9) << 16);
		var height = bytes.get(10) | (bytes.get(11) << 8) | (bytes.get(12) << 16);

		if (width == 0 || height == 0)
		{
			trace('[ASTC] Invalid dimensions: $width x $height');
			return null;
		}

		var format = getFormatConstant(blockX, blockY);
		if (format == 0)
		{
			trace('[ASTC] Unsupported block size: ${blockX}x${blockY}');
			return null;
		}

		// Calculate block count
		var blocksX = Math.ceil(width / blockX);
		var blocksY = Math.ceil(height / blockY);
		var dataSize = blocksX * blocksY * 16;

		if (bytes.length < 16 + dataSize)
		{
			trace('[ASTC] File too small: $file');
			return null;
		}

		// Extract texture data
		var textureData = bytes.sub(16, dataSize);

		// Create GPU texture
		var texture = createGPUTexture(width, height, format, textureData);
		if (texture == null)
		{
			trace('[ASTC] Failed to create GPU texture: $file');
			return null;
		}

		// Create BitmapData from texture and wrap in FlxGraphic
		var bitmapData = BitmapData.fromTexture(texture);
		var flxGraphic = flixel.graphics.FlxGraphic.fromBitmapData(bitmapData, false, file);
		flxGraphic.persist = true;
		flxGraphic.destroyOnNoUse = false;

		// Store info for potential reuse
		astcData.set(file, {
			width: width,
			height: height,
			blockX: blockX,
			blockY: blockY,
			format: format,
			data: textureData
		});

		trace('[ASTC] Loaded: $file (${width}x${height}, ${blockX}x${blockY})');
		return flxGraphic;
		#else
		return null;
		#end
	}

	/**
	 * Check if ASTC extension is supported
	 */
	public static function isSupported():Bool
	{
		#if mobile
		var gl = getGLContext();
		if (gl == null) return false;

		var ext = gl.getExtension("KHR_texture_compression_astc_ldr");
		if (ext == null)
			ext = gl.getExtension("WEBGL_compressed_texture_astc_ldr");

		return ext != null;
		#else
		return false;
		#end
	}

	/**
	 * Get the GL context from FlxG.stage
	 */
	static function getGLContext():Dynamic
	{
		#if lime
		var stage:Dynamic = FlxG.stage;
		if (stage == null || stage.context == null) return null;

		var ctx:Dynamic = stage.context;
		if (Reflect.hasField(ctx, 'gles3'))
			return Reflect.field(ctx, 'gles3');
		if (Reflect.hasField(ctx, 'gl'))
			return Reflect.field(ctx, 'gl');
		#end
		return null;
	}

	/**
	 * Create and upload a GPU texture with ASTC data
	 */
	static function createGPUTexture(width:Int, height:Int, format:Int, data:haxe.io.Bytes):Texture
	{
		#if mobile
		var context = FlxG.stage.context3D;
		if (context == null) return null;

		var gl = getGLContext();
		if (gl == null) return null;

		// Verify ASTC support
		var astcExt = gl.getExtension("KHR_texture_compression_astc_ldr");
		if (astcExt == null)
			astcExt = gl.getExtension("WEBGL_compressed_texture_astc_ldr");
		if (astcExt == null) return null;

		// Create OpenFL texture
		var texture:Texture = context.createTexture(
			width, height, Context3DTextureFormat.COMPRESSED, false, 1);
		if (texture == null) return null;

		// Upload via GL
		#if lime
		var texBase:Dynamic = texture;
		var textureID:Dynamic = null;

		if (Reflect.hasField(texBase, '__textureID'))
			textureID = Reflect.field(texBase, '__textureID');

		if (textureID == null)
		{
			textureID = gl.createTexture();
		}

		gl.bindTexture(gl.TEXTURE_2D, textureID);
		gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);

		// Copy bytes to UInt8Array
		var arr = new UInt8Array(data.length);
		for (i in 0...data.length)
			arr[i] = data.get(i);

		gl.compressedTexImage2D(gl.TEXTURE_2D, 0, format, width, height, 0, arr);

		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.generateMipmap(gl.TEXTURE_2D);

		gl.bindTexture(gl.TEXTURE_2D, null);

		if (Reflect.hasField(texBase, '__textureID'))
			Reflect.setField(texBase, '__textureID', textureID);
		#end

		return texture;
		#else
		return null;
		#end
	}

	/**
	 * Get ASTC format constant for GL
	 * Based on KHR_texture_compression_astc_ldr
	 */
	static function getFormatConstant(blockX:Int, blockY:Int):Int
	{
		return switch (blockX)
		{
			case 4:
				switch (blockY)
				{
					case 4: 0x93B0; // RGBA_ASTC_4x4
					default: 0;
				}
			case 5:
				switch (blockY)
				{
					case 4: 0x93B1; // RGBA_ASTC_5x4
					case 5: 0x93B2; // RGBA_ASTC_5x5
					default: 0;
				}
			case 6:
				switch (blockY)
				{
					case 5: 0x93B3; // RGBA_ASTC_6x5
					case 6: 0x93B4; // RGBA_ASTC_6x6
					default: 0;
				}
			case 8:
				switch (blockY)
				{
					case 5: 0x93B5; // RGBA_ASTC_8x5
					case 6: 0x93B6; // RGBA_ASTC_8x6
					case 8: 0x93B7; // RGBA_ASTC_8x8
					default: 0;
				}
			case 10:
				switch (blockY)
				{
					case 5: 0x93B8;  // RGBA_ASTC_10x5
					case 6: 0x93B9;  // RGBA_ASTC_10x6
					case 8: 0x93BA;  // RGBA_ASTC_10x8
					case 10: 0x93BB; // RGBA_ASTC_10x10
					default: 0;
				}
			case 12:
				switch (blockY)
				{
					case 10: 0x93BC; // RGBA_ASTC_12x10
					case 12: 0x93BD; // RGBA_ASTC_12x12
					default: 0;
				}
			default: 0;
		}
	}

	/**
	 * Clear all cached ASTC data
	 */
	public static function clearCache():Void
	{
		astcData.clear();
	}
}

typedef ASTCTextureInfo = {
	var width:Int;
	var height:Int;
	var blockX:Int;
	var blockY:Int;
	var format:Int;
	var data:haxe.io.Bytes;
}
