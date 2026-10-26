import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
var r = NSRect(x:0,y:0,width:0,height:0)
let cg = img.cgImage(forProposedRect:&r, context:nil, hints:nil)!
let w = Int(a[3])!, h = Int(a[4])!
let c = cg.cropping(to: CGRect(x:0,y:0,width:w,height:h))!
let rep = NSBitmapImageRep(cgImage:c)
try! rep.representation(using:.png, properties:[:])!.write(to: URL(fileURLWithPath:a[2]))
print(c.width, c.height)
