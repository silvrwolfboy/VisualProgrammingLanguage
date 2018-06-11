//
//  Program.swift
//  VPL
//
//  Created by Nathan Flurry on 6/9/18.
//  Copyright © 2018 Nathan Flurry. All rights reserved.
//

import Foundation

public enum InternalRuntimeError: Error {
    case missingStartNode
    case invalidTriggerID
    case stackIsEmpty
    case missingInputValue
    case missingOutputValue
}

class RuntimeStackItem {
    var node: Node
    var callIndex: Int = 0
    var visitAgain: Bool = false
    
    init(node: Node) {
        self.node = node
    }
}

// TODO: Need a way to notify of the updated running state, or just observe it for better performance
// TODO: Should this run on another thread or have the user do it manually

public class ProgramRuntime {
    /// The runtime stack for the running program.
    private var stack: [RuntimeStackItem]
    
    /// If the program is finished.
    public var finished: Bool {
        return stack.count == 0
    }
    
    fileprivate init(startNode: Node) {
        stack = [ RuntimeStackItem(node: startNode) ]
    }
    
    /// Executes the entire program without stopping.
    public func runSync() throws {
        // Keep stepping through the program
        while !finished {
            try step()
        }
    }
    
    /// Executes one step of the program.
    public func step() throws {
        try executeCurrent()
    }
    
    /// Executs a node on the control flow. This cannot execute nodes with value
    /// outputs.
    private func executeCurrent() throws {
        // DEBUG: Print the stack
//        let debugStack = stack.map { type(of: $0.node).name }.joined(separator: ", ")
//        print("Stack: [\(debugStack)]")

        // Find the node to execute
        guard let stackItem = stack.last else {
            throw InternalRuntimeError.stackIsEmpty
        }
        let node = stackItem.node
        
        // Determine if should execute again; otherwise just pop the item and
        // keep travering up the node tree
        guard stackItem.callIndex == 0 || stackItem.visitAgain else {
            stack.removeLast()
            return
        }
        
        // Get results from input data
        let params = try node.inputValues.map { try self.evaluate(value: $0) }
        
        // Execute the node and get the results
        let data = CallData(node: node, params: params, index: stackItem.callIndex)
        let result = try node.exec(call: data)
        stackItem.callIndex += 1 // Increment count if called again
        stackItem.visitAgain = result.visitAgain // Determine if visit again
        
        // Handle the action
        switch result.data {
        case .none:
            // Remove the last node from the stack if reaches an end
            stack.removeLast()
            
        case .exec(let triggerID):
            // Find the trigger
            guard let trigger = node.trigger(id: triggerID) else {
                throw InternalRuntimeError.invalidTriggerID
            }
            
            // Find the target node
            if let targetNode = trigger.target?.owner {
                if trigger.nextTrigger {
                    // Replace the current item on the stack if moving to the next node
                    stack[stack.count - 1] = RuntimeStackItem(node: targetNode)
                } else {
                    // Push the node to the stack if it's a child
                    stack.append(RuntimeStackItem(node: targetNode))
                }
            } else {
                // Remove the last node from the stack if reaches an end
                stack.removeLast()
            }
            
        case .value(_):
            fatalError("Value result cannot exist in control flow execution.")
            
        case .async:
            fatalError("Unimplemented.")
        }
    }
    
    // TODO: Find a way to async execut this so you can step through this
    /// Evaluates nodes that output values from the input socket that points to
    /// the given node.
    func evaluate(value: InputValue) throws -> Value {
        // Get the node for the data
        guard let node = value.target?.owner else {
            throw InternalRuntimeError.missingInputValue
        }
        
        // Evaluate the params
        let params = try node.inputValues.map { try self.evaluate(value: $0) }
        
        // Execute the node; index does not apply to evaluating nodes
        let data = CallData(node: node, params: params, index: 0)
        let result = try node.exec(call: data)
        
        // Handle the result
        if case let .value(value) = result.data {
            return value
        } else {
            throw InternalRuntimeError.missingOutputValue
        }
    }
    
    private func asyncCallback(results: CallResult) {
        fatalError("Unimplemented.")
    }
}

public class Program {
    /// List of all nodes associated with the program.
    public private(set) var nodes: [Node]
    
    /// Finds the starting node.
    var startNode: Node? {
        return nodes.first { $0 is BaseNode }
    }
    
    init(nodes: [Node] = []) {
        self.nodes = nodes
    }
    
    public func create() throws -> ProgramRuntime {
        // Find the start node of the program
        guard let startNode = startNode else {
            throw InternalRuntimeError.missingStartNode
        }
        
        return ProgramRuntime(startNode: startNode)
    }
    
    public func add(node: Node) {
        assert(!nodes.contains { $0 === node })
        
        // Add the node to the array
        nodes.append(node)
    }
    
    public func remove(node: Node) {
        assert(nodes.contains { $0 === node })
        
        // Add the node to the array
        nodes.removeAll { $0 === node }
    }
}
