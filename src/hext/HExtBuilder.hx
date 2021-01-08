package hext;

#if macro
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;
import haxe.macro.Context;
import haxe.macro.Expr;
import hext.HExt;
import haxe.Serializer;

import htmlparser.HtmlParser;
import htmlparser.HtmlNodeElement;
import htmlparser.HtmlNodeText;

using StringTools;
using Lambda;

class HExtBuilder {
    public static var removeChildren = [HExt.removeAttrName];

	public static function addHTML(htmlPath:String):Array<Field> {
		// get existing fields from the context from where build() is called
        var fields = Context.getBuildFields();
		for(curFileName in FileSystem.readDirectory(htmlPath)) {
			var htmlStr = File.getContent(Path.join([htmlPath, curFileName]));

			var fieldName = curFileName;
            if(fieldName.indexOf(".") != -1) fieldName = fieldName.substring(0, fieldName.indexOf("."));
            fieldName = cleanFieldName(fieldName);

			// Recurse fields
            var elements = processChunk_HtmlParser(htmlStr);
            if(elements.length > 0) { // HExt elements found
                // Create a dummy root node that matches the html file name
                var node:HtmlNodeElementExt = {
                    name:fieldName,
                    children:elements,
                    node:null,
                    cloneChildren:elements
                };
                // defineAbstract will recursively create 'wrappers' around the HtmlNodeElement data
                var rootAbstract = defineAbstract(node, ["hext"]);
                var rootField:Field = {
                    name: fieldName,
                    access: [Access.APublic, Access.AStatic],
                    kind: FVar(TPath({pack:rootAbstract.pack, name:rootAbstract.name}), null), 
                    pos: Context.currentPos(),
                };
                fields.push(rootField);
            }
		}
				
		return fields;
    }
    
    static function defineAbstract(childNode:HtmlNodeElementExt, curPack:Array<String>) {
        curPack = curPack.concat([childNode.name]);
        var newAbstract:TypeDefinition = {
            pos:Context.currentPos(),
            pack:curPack,
            name: cleanTypeName(childNode.name),
            kind: TDAbstract(macro:htmlparser.HtmlNodeElement, [macro:htmlparser.HtmlNodeElement], []),
            fields: [],
            meta: [{pos:Context.currentPos(), name:":forward"}, {pos:Context.currentPos(), name:":keepSub"}]
        }

        if(childNode.node != null) {
#if hextclone
            // Create 'clone' method and abstract
            var cloneAbstract = defineAbstract_Clone(childNode, curPack);
            var clone:Field = {
                pos:Context.currentPos(),
                name:"clone",
                kind: FFun({args:[], expr:macro {
                    haxe.Serializer.USE_CACHE = true;
		            return haxe.Unserializer.run(haxe.Serializer.run(this));
                },ret:TPath({pack:cloneAbstract.pack, name:cloneAbstract.name})}), 
                access: [APublic]
            }
            newAbstract.fields.push(clone);
#end

#if hextclonejs
            // Create 'cloneDOM' method
            var cloneDOM:Field = {
                pos:Context.currentPos(),
                name:"cloneDOM",
                kind: FFun({args:[], expr:toDOMElements(childNode),ret:null}), 
                access: [APublic]
            }
            newAbstract.fields.push(cloneDOM);
#end
        }

        // Create handlers for the hext children
        for(child in childNode.children) {
            var childAbstract = defineAbstract(child, curPack);
            var childType = TPath({pack:childAbstract.pack, name:childAbstract.name});

#if hextclone
            // Static field that stores the 'template' node - this will be lazy created by the 'getter'
            var sVar:Field = {
                pos:Context.currentPos(),
                name:"_" + cleanFieldName(child.name),
                kind: FVar(childType, null), 
                access: [AStatic, APrivate]
            }
            newAbstract.fields.push(sVar);
            Serializer.USE_CACHE = true;
            var serializedNode = Serializer.run(child.node);
#end
            // Property to access the 'template'
            var prop:Field = {
                pos:Context.currentPos(),
                name:cleanFieldName(child.name),
                kind: FProp("get","never",childType), 
                access: [APublic]
            }
            
            // Property 'get' function which will lazy create the static instance from the serialized node
            var getFunc:Field = {
                pos:Context.currentPos(),
                name:"get_" + cleanFieldName(child.name),
                kind: FFun({args:[], expr:macro {
#if hextclone
                    if($i{sVar.name} == null) $i{sVar.name} = haxe.Unserializer.run($v{serializedNode});
                    return $i{sVar.name};
#else
                    return null;
#end
                },ret:childType}), 
                access: [APrivate]
            }
            newAbstract.fields.push(prop);
            newAbstract.fields.push(getFunc);
        }

        Context.defineType(newAbstract);

        return newAbstract;
    }

    static function defineAbstract_Clone(childNode:HtmlNodeElementExt, curPack:Array<String>) {
        var newAbstract:TypeDefinition = {
            pos:Context.currentPos(),
            pack:curPack,
            name: cleanTypeName(childNode.name) + "_Clone",
            kind: TDAbstract(macro:htmlparser.HtmlNodeElement, [macro:htmlparser.HtmlNodeElement], [macro:htmlparser.HtmlNodeElement]),
            fields: [],
            meta: [{pos:Context.currentPos(), name:":forward"}]
        }

        // Create handlers for the hext children 'clone's
        for(cloneChild in childNode.cloneChildren) {
            var cloneChildType = TPath({pack:curPack.concat([cloneChild.name]), name:cleanTypeName(cloneChild.name) + "_Clone"});
            // Property to access the cloned child
            var prop:Field = {
                pos:Context.currentPos(),
                name:cleanFieldName(cloneChild.name),
                kind: FProp("get","never",cloneChildType), 
                access: [APublic]
            }
            var getFunc:Field = {
                pos:Context.currentPos(),
                name:"get_" + cleanFieldName(cloneChild.name),
                kind: FFun({args:[], expr:macro {
                    return hext.HExt.findNode(this, $v{cloneChild.name});
                },ret:cloneChildType}), 
                access: [APrivate]
            }
            newAbstract.fields.push(prop);
            newAbstract.fields.push(getFunc);
        }

        Context.defineType(newAbstract);

        return newAbstract;
    }

    static function toDOMElements(node:HtmlNodeElementExt, ignoreAttrs:Array<String> = null):haxe.macro.Expr {
        if(ignoreAttrs == null) ignoreAttrs = [ HExt.defaultAttrName, HExt.removeAttrName ];
        var exprs:Array<Expr> = [];
        
        var elementCount = 0;
        function recurseChildren(nodeExt:HtmlNodeElementExt, node:HtmlNodeElement = null, parentVar:String = null, curProps:Array<ObjectField> = null) {
            if(node == null) node = nodeExt.node;

            // Create this element
            var tempName = 't$elementCount';
            elementCount++;
            // Build Haxe js.html type to help with code completion
            var finalType = checkType(node.name);
            var createExpr:Expr = macro js.Browser.document.createElement($v{node.name});
            var assignExpr:Expr = {expr:ECast(createExpr, finalType), pos:Context.currentPos()};
            var castExpr:Expr = {expr:ECast(macro $i{tempName}, finalType), pos:Context.currentPos()};
            var varExpr:Expr = {
                pos:Context.currentPos(),
                expr: EVars([{
                    type:finalType,
                    name:tempName,
                    expr:assignExpr
                }])
            };
            exprs.push(macro var $tempName = js.Browser.document.createElement($v{node.name}));
            for(attr in node.attributes.filter((a) -> ignoreAttrs.indexOf(a.name) == -1)) {
                exprs.push(macro $i{tempName}.setAttribute($v{attr.name}, $v{attr.value}));
            }

            // curProps is null, this is the top-level node so always save it
            if(curProps == null) {
                curProps = [];
                curProps.push({field:"_",expr:castExpr});
            } else {
                // Check for a 'cloneChild' - this is a named child of the level above
                var cloneChild = nodeExt.cloneChildren.find((c) -> c.node == node);
                if(cloneChild != null) {
                    var newProps:Array<ObjectField> = [ {field:"_",expr:castExpr} ];
                    curProps.push({field:cloneChild.name,expr:{expr:EObjectDecl(newProps), pos:Context.currentPos()}});
                    curProps = newProps; // Reset curProps so children get added properly
                    nodeExt = cloneChild; // Set the cloneChild to be the 'parent' of everything below it
                }
            }

            // If there's a parent element, appendChild
            if(parentVar != null) exprs.push(macro $i{parentVar}.appendChild($i{tempName}));

            // Add children
            for(c in node.nodes) {
                if(Std.is(c, HtmlNodeElement)) {
                    recurseChildren(nodeExt, cast c, tempName, curProps);
                } else if(Std.is(c, HtmlNodeText)) {
                    var nt:HtmlNodeText = cast c;
                    exprs.push(macro $i{tempName}.appendChild(js.Browser.document.createTextNode($v{nt.text})));
                }
            }
            return curProps;
        }
        var outProps = recurseChildren(node);
        var outExp:Expr = {expr:EObjectDecl(outProps), pos:Context.currentPos()};
        var retExp:Expr = {expr:EReturn(outExp), pos:Context.currentPos()};
        exprs.push(retExp);
        return macro $b{exprs};
    }

    static function processChunk_HtmlParser(chunk:String, attrName:String = HExt.defaultAttrName, removeChildrenAttrs:Array<String> = null):Array<HtmlNodeElementExt> {
        if(removeChildrenAttrs == null) removeChildrenAttrs = removeChildren;
        var htmlParsed = HtmlParser.run(chunk);
        var node:HtmlNodeElement = cast htmlParsed.find((n) -> Std.is(n, HtmlNodeElement));
        return processElement_HtmlParser(node, attrName, removeChildrenAttrs);
    }

    static function processElement_HtmlParser(parent:HtmlNodeElement, attrName:String = HExt.defaultAttrName, removeChildrenAttrs:Array<String> = null, parentExt:HtmlNodeElementExt = null):Array<HtmlNodeElementExt> {
        var elements:Array<HtmlNodeElementExt> = [];
        if(parent != null) {
            // Clean whitespace
            for(c in [ for(n in parent.nodes) n ]) {
                if(Std.is(c, HtmlNodeText)) {
                    var nt:HtmlNodeText = cast c;
                    if(nt.text.trim().length == 0) nt.remove();
                }
            }
            if(removeChildrenAttrs == null) removeChildrenAttrs = removeChildren;
            if(parent.hasAttribute(attrName)) {
                parentExt = {name:parent.getAttribute(attrName), node:parent, children:[], cloneChildren:[]};
                elements.push(parentExt);
            }
            for(attr in removeChildrenAttrs) {
                if(parent.hasAttribute(attr)) {
                    parent.remove();
                }
            }
            for(child in [ for(c in parent.children) c ]) { // Make a copy of children so if the children are removed the iterator won't fail
                var childElements = processElement_HtmlParser(child, attrName, removeChildrenAttrs, parentExt);
                if(parentExt != null) {
                    for(ce in childElements) {
                        parentExt.children.push(ce);
                        var cloneChild = true;
                        for(attr in removeChildrenAttrs) if(ce.node.hasAttribute(attr)) cloneChild = false;
                        if(cloneChild) parentExt.cloneChildren.push(ce);
                    }
                } else {
                    for(ce in childElements) elements.push(ce);
                }
            }
        }
        return elements;
    }

    static function cleanTypeName(name:String) {
        name = name.replace(" ", "_");
        name = name.substr(0, 1).toUpperCase() + name.substr(1);
        return name;
    }

    static function cleanFieldName(name:String) {
        name = name.replace(" ", "_").replace(".", "_");
        name = name.substr(0, 1).toLowerCase() + name.substr(1);
        return name;
    }

    static function checkType(type:String):ComplexType {
        return switch(type) {
            // TODO: automate this?
            case "table": TPath({pack:["js","html"], name:"TableElement"});
            case "tr": TPath({pack:["js","html"], name:"TableRowElement"});
            case "td": TPath({pack:["js","html"], name:"TableCellElement"});
            case _: TPath({pack:["js","html"], name:"Element"});
        }
    }
}

typedef HtmlNodeElementExt = {
    name:String,
    node:HtmlNodeElement, // Raw node template - this may have children removed/etc based on hext-remove attribute
    children:Array<HtmlNodeElementExt>, // Child list of hext named elements
    cloneChildren:Array<HtmlNodeElementExt> // Child list of hext elements that do not have hext-remove attribute
}

#end

