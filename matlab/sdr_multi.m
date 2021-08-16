function [bound, time,status] = sdr_multi(net,X_min,X_max,label,target,options)

% solves a semidefintie relaxation of certified robustness based on the
% following paper
%  Raghunathan, Aditi, Jacob Steinhardt, and Percy S. Liang. "Semidefinite relaxations for certifying robustness to adversarial examples." Advances in Neural Information Processing Systems. 2018.


if(~strcmp(net.activation,'relu'))
    error('The method deep sdr is only supported for ReLU activation functions');
end

if(~isa(net,'nnsequential'))
    error('The net object must of be of the class nnsequential');
end

%%
language = options.language;
solver = options.solver;
verbose = options.verbose;

weights = net.weights;
biases = net.biases;
dims = net.dims;
dim_out = dims(end);
%% interval arithmetic
% u and l will be the lower and upper bounds on the preactivation values

num_layers = length(net.dims)-2;

k = 1;
x_min{k} = X_min;
x_max{k} = X_max;

for k=1:num_layers+1
    y_min{k} = max(net.weights{k},0)*x_min{k}+min(net.weights{k},0)*x_max{k}+net.biases{k}(:);
    y_max{k} = min(net.weights{k},0)*x_min{k}+max(net.weights{k},0)*x_max{k}+net.biases{k}(:);

    if(k<=num_layers)
        x_min{k+1} = max(y_min{k},0);
        x_max{k+1} = max(y_max{k},0);
    end
end

num_hidden_layers = length(dims)-2;

% for i = 1: num_hidden_layers
%     In_i = find(x_max{i + 1} <= 0);
%     cp_In_i = setdiff(1: dims(i + 1),In_i);
%     weights{i} = weights{i}(cp_In_i, :);
%     weights{i + 1} = weights{i + 1}(:, cp_In_i);
%     biases{i} = biases{i}(cp_In_i);
%     x_min{i + 1} = x_min{i +1}(cp_In_i);
%     x_max{i + 1} = x_max{i +1}(cp_In_i);
%     dims(i + 1) = dims(i + 1) - length(In_i);
% end

%% define descision variables
size_big_matrix = 1 + sum(dims(1:end-1));
M = sdpvar(size_big_matrix, size_big_matrix,'symmetric');
constraints = [M >=0, M(1, 1) == 1];
x = M(1, 2: 1+dims(1)).';
X = M(2: 1 + dims(1), 2: 1 + dims(1));

%Input constraints
constraints = [constraints, x>=x_min{1}];
constraints = [constraints, x<=x_max{1}];
constraints = [constraints, (diag(X) - (x_min{1} + x_max{1}).*x ...
+ x_min{1}.*x_max{1} <= 0)];

current_pos_matrix = 1;

for i = 1:num_hidden_layers
    W_i = weights{i};
    b_i = biases{i};
    input_span = 1 + current_pos_matrix: current_pos_matrix + dims(i);
    output_span = 1 + current_pos_matrix + dims(i): current_pos_matrix + dims(i) + dims(i+1);
    input_linear = M(1, input_span).';
    output_linear = M(1, output_span).';
    input_quadratic = M(input_span, input_span);
    output_quadratic = M(output_span, output_span);
    cross_terms = M(input_span, output_span);

%    k_i = (x_max{i + 1} - x_min{i + 1}) ./ (y_max{i} - y_min{i})
%    constraints = [constraints, output_linear <= k_i .* (W_i * input_linear + b_i - y_min{i}) + x_min{i + 1}]

%     xxT = [1; input_linear; output_linear] * [1; input_linear; output_linear]';
%     constraints = [constraints, M >= xxT];

    % ReLU linear constraints
    constraints = [constraints, output_linear >= W_i*input_linear + b_i];
    constraints = [constraints, output_linear >=0];
    % ReLU quadratic constraints
    temp_matrix = W_i*cross_terms;
    constraints = [constraints, diag(output_quadratic) == diag(temp_matrix) + output_linear.*b_i, diag(output_quadratic) >= 0, diag(input_quadratic)>=0];

    % layerwise constraints
    constraints = [constraints, (diag(output_quadratic) - (x_min{i+1} + x_max{i+1}).*output_linear ...
				 + x_min{i+1}.*x_max{i+1} <= 0)];

    current_pos_matrix = current_pos_matrix + dims(i);


    constraints = [constraints, diag(output_quadratic) - diag(temp_matrix) - b_i.*output_linear - x_min{i+1}.*output_linear + (W_i*input_linear).*x_min{i+1} + x_min{i+1}.*b_i<=0];


end

% Constructing the objective
dim_final = dims(end-1);
y_final = M(1, 1 + current_pos_matrix: current_pos_matrix + dim_final).';

c = zeros(dim_out,1);
%c(label) = -1;
%c(target) = 1;
if label == 1
   c(1) = 1;
end
if label == 2
   c(1) = -1;
end

obj = c.'*(weights{end}*y_final + biases{end});
disp("Solving problem --SDR")
options = sdpsettings('solver',solver,'verbose',verbose, 'dualize', 1);
out = optimize(constraints,-obj,options);
bound = value(obj);
if label == 2
       bound = -bound;
end
%out_op = value(M(1,:))';
%save("optimal.mat","out_op");
% disp(value(M));
time= out.solvertime;
status = out.info;

%% solve the problem


message = ['method: sdr', '| solver: ', solver, '| bound: ', num2str(bound), '| time: ', num2str(time), '| status: ', status];
disp(message);


end