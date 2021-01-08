package hext;

#if hextclone
import htmlparser.HtmlNodeElement;
#end
using Lambda;

#if js
import js.html.Element;
import js.Browser.document;
import htmlparser.HtmlNodeText;
#end

class HExt {
    public static inline var attr = "hext";
    public static inline var removeAttr = "hext-remove";
    public static inline var removeChildrenAttr = "hext-remove-children";

#if hextclone
    public static function findNode(node:HtmlNodeElement, nodeType:String, attrName:String = attr) {
        if(node != null) {
            if(node.hasAttribute(attrName) && node.getAttribute(attrName) == nodeType) return node;
            for(child in node.children) {
                var n = findNode(child, nodeType, attrName);
                if(n != null) return n;
            }
        }
        return null;
    }

    #if js
    public static function toElement(node:HtmlNodeElement, elementMap:Map<String,Array<Element>> = null, attrName:String = attr, ignoreAttrs:Array<String> = null):Element {
        if(ignoreAttrs == null) ignoreAttrs = [ attr, removeAttr, removeChildrenAttr ];
        var element = document.createElement(node.name);
        if(elementMap != null && node.hasAttribute(attrName)) {
            var name = node.getAttribute(attrName);
            if(!elementMap.exists(name)) elementMap.set(node.getAttribute(attrName), []);
            elementMap[name].push(element);
        }
        for(attr in node.attributes.filter((a) -> ignoreAttrs.indexOf(a.name) == -1)) element.setAttribute(attr.name, attr.value);
        for(c in node.nodes) {
            if(Std.is(c, HtmlNodeElement)) {
                element.appendChild(toElement(cast c, elementMap, attrName, ignoreAttrs));
            } else if(Std.is(c, HtmlNodeText)) {
                var tn:HtmlNodeText = cast c;
                element.appendChild(document.createTextNode(tn.text));
            }
        }
        return element;
    }

    public static function toElementMap(node:HtmlNodeElement, attrName:String = attr, ignoreAttrs:Array<String> = null):{root:Element, map:Map<String,Array<Element>>} {
        var map:Map<String,Array<Element>> = [];
        return {root:toElement(node, map, attrName, ignoreAttrs), map:map};
    }
    #end
#end
}
