import htmlparser.*;
import haxe.*;

class MainTest {
	static function main() {
        var s = $v{PreSerialize.serializeHtml("<p>serialized</p>")};
		trace(s);
		var n2:Array<HtmlNode> = Unserializer.run(s);
		trace(n2);
	}
}

class PreSerialize {
    macro public static inline function serializeHtml(html:String):haxe.macro.Expr {
        haxe.Serializer.USE_CACHE = true;
        return macro $v{Serializer.run(HtmlParser.run(html))};
    }
}
