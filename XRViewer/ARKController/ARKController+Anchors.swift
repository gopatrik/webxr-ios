@objc extension ARKController {
    
    // MARK: - Anchor Dictionaries
    
    func updateDictionary(for updatedAnchor: ARAnchor) {
        let anchorID = self.anchorID(for: updatedAnchor)
        guard let anchorDictionary = objects[anchorID] as? NSMutableDictionary else { return }
        anchorDictionary[WEB_AR_TRANSFORM_OPTION] = updatedAnchor.transform.array()

        if updatedAnchor is ARPlaneAnchor {
            // ARKit system plane anchor
            guard let updatedPlaneAnchor = updatedAnchor as? ARPlaneAnchor else { return }
            updatePlaneAnchorData(updatedPlaneAnchor, toDictionary: anchorDictionary)
        } else if updatedAnchor is ARImageAnchor {
            // User generated ARImageAnchor, do nothing more than updating the transform
            return
        } else if updatedAnchor is ARFaceAnchor {
            // System generated ARFaceAnchor
            guard let faceAnchor = updatedAnchor as? ARFaceAnchor else { return }
            updateFaceAnchorData(faceAnchor, to: anchorDictionary)
        } else {
            // Simple, user generated ARAnchor, do nothing more than updating the transform
            return
        }
    }
    
    func createDictionary(for addedAnchor: ARAnchor) -> NSDictionary {
        let anchorDictionary = NSMutableDictionary.init()
        anchorDictionary[WEB_AR_TRANSFORM_OPTION] = addedAnchor.transform.array()
        anchorDictionary[WEB_AR_MUST_SEND_OPTION] = shouldSend(addedAnchor) ? NSNumber(value: true) : NSNumber(value: false)
        
        if addedAnchor is ARPlaneAnchor {
            // ARKit system plane anchor
            guard let addedPlaneAnchor = addedAnchor as? ARPlaneAnchor else { return anchorDictionary }
            addPlaneAnchorData(addedPlaneAnchor, toDictionary: anchorDictionary)
            anchorDictionary[WEB_AR_UUID_OPTION] = addedAnchor.identifier.uuidString
            anchorDictionary[WEB_AR_ANCHOR_TYPE] = "plane"
            DDLogDebug("Add Plane Anchor - \(addedAnchor.identifier.uuidString)")
        } else if addedAnchor is ARImageAnchor {
            // User generated ARImageAnchor
            let addedImageAnchor = addedAnchor as? ARImageAnchor
            arkitGeneratedAnchorIDUserAnchorIDMap[addedAnchor.identifier.uuidString] = addedImageAnchor?.referenceImage.name
            anchorDictionary[WEB_AR_UUID_OPTION] = addedImageAnchor?.referenceImage.name
            anchorDictionary[WEB_AR_ANCHOR_TYPE] = "image"
        } else if addedAnchor is ARFaceAnchor {
            // System generated ARFaceAnchor
            guard let faceAnchor = addedAnchor as? ARFaceAnchor else { return anchorDictionary }
            addFaceAnchorData(faceAnchor, toDictionary: anchorDictionary)
            anchorDictionary[WEB_AR_UUID_OPTION] = faceAnchor.identifier.uuidString
            anchorDictionary[WEB_AR_ANCHOR_TYPE] = "face"
        } else {
            // Simple, user generated ARAnchor
            let userAnchorID = arkitGeneratedAnchorIDUserAnchorIDMap?[addedAnchor.identifier.uuidString] as? String
            let name = userAnchorID != nil ? userAnchorID : addedAnchor.identifier.uuidString
            anchorDictionary[WEB_AR_UUID_OPTION] = name ?? ""
            anchorDictionary[WEB_AR_ANCHOR_TYPE] = "anchor"
            DDLogDebug("Add User Anchor - \(String(describing: name))")
        }
        
        return anchorDictionary
    }
    
    // MARK: - Face Anchors
    
    // Tony: Commenting this out, conversion to Swift is causing issues again.
    // Tried several resolutions, none worked so far. Leaving original in place for the moment.
//    func updateFaceAnchorData(_ faceAnchor: ARFaceAnchor, toDictionary faceAnchorDictionary: NSMutableDictionary) {
//        var geometryDictionary: [AnyHashable: Any]? = faceAnchorDictionary[WEB_AR_GEOMETRY_OPTION] as? Dictionary
//        if geometryDictionary == nil {
//            geometryDictionary = [AnyHashable: Any]()
//            faceAnchorDictionary[WEB_AR_GEOMETRY_OPTION] = geometryDictionary
//        }
//        let vertices = NSMutableArray.init(capacity: faceAnchor.geometry.vertices.count)
//        for i in 0..<faceAnchor.geometry.vertices.count {
//            vertices.add(faceAnchor.geometry.vertices[i].dictionary())
//        }
//        geometryDictionary?["vertices"] = vertices
//
//        guard let blendShapesDictionary = faceAnchorDictionary[WEB_AR_BLEND_SHAPES_OPTION] as? NSMutableArray else { return }
//        setBlendShapes(faceAnchor.blendShapes as NSDictionary, toArray: blendShapesDictionary)
//
//        // Remove the rest of the geometry data, since it doesn't change
//        geometryDictionary?["vertexCount"] = nil
//        geometryDictionary?["textureCoordinateCount"] = nil
//        geometryDictionary?["textureCoordinates"] = nil
//        geometryDictionary?["triangleCount"] = nil
//        geometryDictionary?["triangleIndices"] = nil
//    }
    
    func addFaceAnchorData(_ faceAnchor: ARFaceAnchor, toDictionary faceAnchorDictionary: NSMutableDictionary) {
        let blendShapesArray = NSMutableArray.init()
        setBlendShapes(faceAnchor.blendShapes as NSDictionary, toArray: blendShapesArray)
        faceAnchorDictionary[WEB_AR_BLEND_SHAPES_OPTION] = blendShapesArray
        
        let geometryDictionary = NSMutableDictionary.init()
        addFaceGeometryData(faceAnchor.geometry, toDictionary: geometryDictionary)
        faceAnchorDictionary[WEB_AR_GEOMETRY_OPTION] = geometryDictionary
    }
    
    func addFaceGeometryData(_ faceGeometry: ARFaceGeometry, toDictionary geometryDictionary: NSMutableDictionary) {
        geometryDictionary["vertexCount"] = faceGeometry.vertices.count
        
        let vertices = NSMutableArray.init(capacity: faceGeometry.vertices.count)
        for i in 0..<faceGeometry.vertices.count {
            vertices.add(faceGeometry.vertices[i].dictionary())
        }
        geometryDictionary["vertices"] = vertices
        
        let textureCoordinates = NSMutableArray.init(capacity: faceGeometry.textureCoordinates.count)
        geometryDictionary["textureCoordinateCount"] = faceGeometry.textureCoordinates.count
        for i in 0..<faceGeometry.textureCoordinates.count {
            textureCoordinates.add(faceGeometry.textureCoordinates[i].dictionary())
        }
        geometryDictionary["textureCoordinates"] = textureCoordinates
        
        geometryDictionary["triangleCount"] = faceGeometry.triangleCount
        
        let triangleIndices = NSMutableArray.init(capacity: faceGeometry.triangleCount * 3)
        for i in 0..<faceGeometry.triangleCount * 3 {
            triangleIndices.add(faceGeometry.triangleIndices[i])
        }
        geometryDictionary["triangleIndices"] = triangleIndices
    }
    
    func setBlendShapes(_ blendShapes: NSDictionary, toArray blendShapesArray: NSMutableArray) {
        let blendShapesArray = blendShapesArray
        blendShapesArray[0] = blendShapes[ARFaceAnchor.BlendShapeLocation.browDownLeft] ?? 0
        blendShapesArray[1] = blendShapes[ARFaceAnchor.BlendShapeLocation.browDownRight] ?? 0
        blendShapesArray[2] = blendShapes[ARFaceAnchor.BlendShapeLocation.browInnerUp] ?? 0
        blendShapesArray[3] = blendShapes[ARFaceAnchor.BlendShapeLocation.browOuterUpLeft] ?? 0
        blendShapesArray[4] = blendShapes[ARFaceAnchor.BlendShapeLocation.browOuterUpRight] ?? 0
        blendShapesArray[5] = blendShapes[ARFaceAnchor.BlendShapeLocation.cheekPuff] ?? 0
        blendShapesArray[6] = blendShapes[ARFaceAnchor.BlendShapeLocation.cheekSquintLeft] ?? 0
        blendShapesArray[7] = blendShapes[ARFaceAnchor.BlendShapeLocation.cheekSquintRight] ?? 0
        blendShapesArray[8] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeBlinkLeft] ?? 0
        blendShapesArray[9] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeBlinkRight] ?? 0
        blendShapesArray[10] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookDownLeft] ?? 0
        blendShapesArray[11] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookDownRight] ?? 0
        blendShapesArray[12] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookInLeft] ?? 0
        blendShapesArray[13] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookInRight] ?? 0
        blendShapesArray[14] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookOutLeft] ?? 0
        blendShapesArray[15] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookOutRight] ?? 0
        blendShapesArray[16] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookUpLeft] ?? 0
        blendShapesArray[17] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeLookUpRight] ?? 0
        blendShapesArray[18] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeSquintLeft] ?? 0
        blendShapesArray[19] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeSquintRight] ?? 0
        blendShapesArray[20] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeWideLeft] ?? 0
        blendShapesArray[21] = blendShapes[ARFaceAnchor.BlendShapeLocation.eyeWideRight] ?? 0
        blendShapesArray[22] = blendShapes[ARFaceAnchor.BlendShapeLocation.jawForward] ?? 0
        blendShapesArray[23] = blendShapes[ARFaceAnchor.BlendShapeLocation.jawLeft] ?? 0
        blendShapesArray[24] = blendShapes[ARFaceAnchor.BlendShapeLocation.jawOpen] ?? 0
        blendShapesArray[25] = blendShapes[ARFaceAnchor.BlendShapeLocation.jawRight] ?? 0
        blendShapesArray[26] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthClose] ?? 0
        blendShapesArray[27] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthDimpleLeft] ?? 0
        blendShapesArray[28] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthDimpleRight] ?? 0
        blendShapesArray[29] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthFrownLeft] ?? 0
        blendShapesArray[30] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthFrownRight] ?? 0
        blendShapesArray[31] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthFunnel] ?? 0
        blendShapesArray[32] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthLeft] ?? 0
        blendShapesArray[33] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthLowerDownLeft] ?? 0
        blendShapesArray[34] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthLowerDownRight] ?? 0
        blendShapesArray[35] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthPressLeft] ?? 0
        blendShapesArray[36] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthPressRight] ?? 0
        blendShapesArray[37] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthPucker] ?? 0
        blendShapesArray[38] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthRight] ?? 0
        blendShapesArray[39] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthRollLower] ?? 0
        blendShapesArray[40] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthRollUpper] ?? 0
        blendShapesArray[41] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthShrugLower] ?? 0
        blendShapesArray[42] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthShrugUpper] ?? 0
        blendShapesArray[43] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthSmileLeft] ?? 0
        blendShapesArray[44] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthSmileRight] ?? 0
        blendShapesArray[45] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthStretchLeft] ?? 0
        blendShapesArray[46] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthStretchRight] ?? 0
        blendShapesArray[47] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthUpperUpLeft] ?? 0
        blendShapesArray[48] = blendShapes[ARFaceAnchor.BlendShapeLocation.mouthUpperUpRight] ?? 0
        blendShapesArray[49] = blendShapes[ARFaceAnchor.BlendShapeLocation.noseSneerLeft] ?? 0
        blendShapesArray[50] = blendShapes[ARFaceAnchor.BlendShapeLocation.noseSneerRight] ?? 0
    }
    
    // MARK: - Plane Anchors
    
    func updatePlaneGeometryData(_ planeGeometry: ARPlaneGeometry, toDictionary planeGeometryDictionary: NSMutableDictionary) {
        
        planeGeometryDictionary["vertexCount"] = NSNumber(value: planeGeometry.vertices.count)
        let vertices = NSMutableArray.init(capacity: planeGeometry.vertices.count)
        for i in 0..<planeGeometry.vertices.count {
            vertices.add(planeGeometry.vertices[i].dictionary())
        }
        planeGeometryDictionary["vertices"] = vertices
        
        let textureCoordinates = NSMutableArray.init(capacity: planeGeometry.textureCoordinates.count)
        planeGeometryDictionary["textureCoordinateCount"] = NSNumber(value: planeGeometry.textureCoordinates.count)
        for i in 0..<planeGeometry.textureCoordinates.count {
            textureCoordinates.add(planeGeometry.textureCoordinates[i].dictionary())
        }
        planeGeometryDictionary["textureCoordinates"] = textureCoordinates
        
        planeGeometryDictionary["triangleCount"] = NSNumber(value: planeGeometry.triangleCount)
        let triangleIndices = NSMutableArray.init(capacity: planeGeometry.triangleCount * 3)
        for i in 0..<planeGeometry.triangleCount * 3 {
            triangleIndices.add(NSNumber(value: planeGeometry.triangleIndices[i]))
        }
        planeGeometryDictionary["triangleIndices"] = triangleIndices
        
        planeGeometryDictionary["boundaryVertexCount"] = NSNumber(value: planeGeometry.boundaryVertices.count)
        let boundaryVertices = NSMutableArray.init(capacity: planeGeometry.boundaryVertices.count)
        for i in 0..<planeGeometry.boundaryVertices.count {
            boundaryVertices.add(planeGeometry.boundaryVertices[i].dictionary())
        }
        planeGeometryDictionary["boundaryVertices"] = boundaryVertices
    }
    
    func addGeometryData(_ planeGeometry: ARPlaneGeometry, toDictionary dictionary: NSMutableDictionary) {
        let geometryDictionary = NSMutableDictionary.init()
        updatePlaneGeometryData(planeGeometry, toDictionary: geometryDictionary)
        dictionary[WEB_AR_GEOMETRY_OPTION] = geometryDictionary
    }
    
    func addPlaneAnchorData(_ planeAnchor: ARPlaneAnchor, toDictionary dictionary: NSMutableDictionary) {
        dictionary[WEB_AR_PLANE_CENTER_OPTION] = planeAnchor.center.dictionary()
        dictionary[WEB_AR_PLANE_EXTENT_OPTION] = planeAnchor.extent.dictionary()
        dictionary[WEB_AR_PLANE_ALIGNMENT_OPTION] = planeAnchor.alignment.rawValue
        addGeometryData(planeAnchor.geometry, toDictionary: dictionary)
    }
    
    func updatePlaneAnchorData(_ planeAnchor: ARPlaneAnchor, toDictionary planeAnchorDictionary: NSMutableDictionary) {
        planeAnchorDictionary[WEB_AR_PLANE_CENTER_OPTION] = planeAnchor.center.dictionary()
        planeAnchorDictionary[WEB_AR_PLANE_EXTENT_OPTION] = planeAnchor.extent.dictionary()
        planeAnchorDictionary[WEB_AR_PLANE_ALIGNMENT_OPTION] = planeAnchor.alignment.rawValue
        guard let geometry = planeAnchorDictionary[WEB_AR_GEOMETRY_OPTION] as? NSMutableDictionary else { return }
        updatePlaneGeometryData(planeAnchor.geometry, toDictionary: geometry)
    }
    
    // MARK: - Anchor Removal
    
    func removeAllAnchors() {
        clearImageDetectionDictionaries()
        
        guard let currentFrame = session?.currentFrame else { return }
        
        for anchor in currentFrame.anchors {
            session?.remove(anchor: anchor)
        }
    }
    
    func removeAllAnchorsExceptPlanes() {
        clearImageDetectionDictionaries()
        
        guard let currentFrame = session?.currentFrame else { return }
        
        for anchor in currentFrame.anchors {
            if !(anchor is ARPlaneAnchor) {
                session?.remove(anchor: anchor)
            }
        }
    }
    
    // MARK: - Helpers
    
    func getAnchorFromARKitAnchorID(_ arkitAnchorID: String) -> ARAnchor? {
        var anchor: ARAnchor? = nil
        guard let currentFrame: ARFrame = session?.currentFrame else { return nil }
        for currentAnchor in currentFrame.anchors {
            if currentAnchor.identifier.uuidString == arkitAnchorID {
                anchor = currentAnchor
                break
            }
        }
        return anchor
    }
    
    func getAnchorFromUserAnchorID(_ userAnchorID: String) -> ARAnchor? {
        var anchor: ARAnchor? = nil
        arkitGeneratedAnchorIDUserAnchorIDMap.enumerateKeysAndObjects { arkitID, userID, stop in
            guard let userID = userID as? String else { return }
            guard let arkitID = arkitID as? String else { return }
            if userID == userAnchorID {
                guard let currentFrame = self.session?.currentFrame else { return }
                let anchors = currentFrame.anchors
                for currentAnchor in anchors {
                    if currentAnchor.identifier.uuidString == arkitID {
                        anchor = currentAnchor
                        break
                    }
                }
                stop.pointee = true
            }
        }
        return anchor
    }
    
    func anchorID(for anchor: ARAnchor) -> String {
        var anchorID: String
        if anchor is ARPlaneAnchor {
            // ARKit system plane anchor
            anchorID = anchor.identifier.uuidString
        } else if anchor is ARImageAnchor {
            // User generated ARImageAnchor
            let imageAnchor = anchor as? ARImageAnchor
            anchorID = imageAnchor?.referenceImage.name ?? ""
        } else if anchor is ARFaceAnchor {
            // System generated ARFaceAnchor
            anchorID = anchor.identifier.uuidString
        } else {
            // Simple, user generated ARAnchor
            let userAnchorID = arkitGeneratedAnchorIDUserAnchorIDMap?[anchor.identifier.uuidString] as? String
            //        NSString *anchorName = anchor.name;
            //        NSString *name;
            //        if (userAnchorID) {
            //            name = userAnchorID;
            //        } else {
            //            name = [anchor.identifier UUIDString];
            //        }
            let name = userAnchorID != nil ? userAnchorID! : anchor.identifier.uuidString
            anchorID = name
        }
        
        return anchorID
    }
    
    /**
     By default, set NO to all the ARAnchor types considered "World sensing data", so they
     won't be sent to JS unless the user allows for that.
     
     @param anchor The anchor to be analyzed
     @return A boolean indicating whether the anchor should be sent to JS or not
     */
    func shouldSend(_ anchor: ARAnchor) -> Bool {
        var shouldSend: Bool
        if anchor is ARPlaneAnchor {
            // ARKit system plane anchor
            #if SEND_PLANES_BY_DEFAULT
            shouldSend = true
            #else
            shouldSend = false
            #endif
        } else if anchor is ARImageAnchor {
            // User generated ARImageAnchor
            shouldSend = false
        } else if anchor is ARFaceAnchor {
            shouldSend = false
            // System generated ARFaceAnchor
        } else {
            // Simple, user generated ARAnchor
            shouldSend = true
        }
        
        return shouldSend
    }
    
    func anyPlaneAnchor(_ anchorArray: [ARAnchor]) -> Bool {
        var anyPlaneAnchor = false
        for anchor: ARAnchor in anchorArray {
            if anchor is ARPlaneAnchor {
                anyPlaneAnchor = true
                break
            }
        }
        return anyPlaneAnchor
    }
}