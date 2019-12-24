---
layout: post
title: Event Hub Consumer Throughput Analysis 
author: haluk.aktas@eepnetwork.om
---

## Introduction

In this document we are going to analyze various strategies to increase the throughput in a sample EventHub consumer application. We will try out various scenarios, starting with a baseline to compare results against. During the tests, the `Prometheus` metric scrape interval is set to 10 seconds. Also, the `Grafana` dashboards display the latest 15 minutes for each individual task with 10 seconds refresh interval. Each test scenario based on the customization made to the single partition event hub consumer code snippet. In order to see the effects of our improvements, we dedicated event hub sender to send events only to single partition. So, we can say there is no event hub partition parallelism during our tests. In addition to these, we have used [Event Processor Host](https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-event-processor-host) which is an agent for .NET consumers that manages partition access and per partition offset for consumers.

## 1. Baseline

In the baseline scenario, there is no parallelism. Each event received in a batch is coming from a single partition on EventHub and processed individually. Processing is considered done when the message is written to both to a Service Bus Topic and Storage Container Location for archiving purposes. And lastly, written to a storage checkpoint.
Total duration for each message is calculated in order to check approximately the total time for processing message is equal to sum of blob, checkpoint and service bus send operation times.
i.e. Total Duration = Duration for Blob Operation + Duration for Service Bus operation + Duration for Checkpoint.

### 1.1 Metrics Used

We use various metrics to observe the intended behavior. In this section we will introduce them. There are currently 4 Prometheus gauge and 1 counter metrics. Gauge metrics are used to view the total duration (in msec) for each defined stopwatch timer. The counter metric is used for counting each batch of events processed by EventProcessorHost instance. Detailed info for each metric is in the following table.

|      Metric Name         | 					Description						    |  Unit |
|        ---        	   |  					    ---      					    |  ---  |
| total_stopwatch          | `Total duration for a batch of events. Approximately`  |  msec |
| servicebus_stopwatch     | `Duration for an event to store it in service bus`     |  msec |
| blobstorage_stopwatch    | `Duration for an event to store it in blob storage`    |  msec |
| checkpoint_stopwatch 	   | `Duration for checkpointing a single batch of events`  |  msec |
| processed_messagecounter | `Messages processed by a second`     				    |  msec |

### 1.1.1 Irate

This graph, named irate, displays the per second instant rate calculated from the processed_messagecounter metric. The method of calculation is called `irate` in Prometheus parlance, which is the rate calculation function. It only looks at the last two points within the range passed to it and calculates a per-second rate. This graph is used to verify whether the rate value at any scrape point is correlated to the calculated total duration at that corresponding scrape point on 	stopwatch timer graph. Rather than inspecting each scrape point individually, we can take the average values into account to grasp better understanding from the comparison.

![serial baseline irate.](/blog/images/eventhub-consumer-blog-ss/serial_irate_baseline.png)

### 1.1.2 Stopwatch Timers

As we can see in the following graph, the total msec last for each event approximately equals to the sum of blob, checkpoint and service bus duration in msec.

![serial baseline stopwatches.](/blog/images/eventhub-consumer-blog-ss/serial_stopwatch_baseline.png)


### 1.1.3 Irate and Total Stopwatch Timer Verification

In order to verify if Prometheus irate graph correlates with our calculation, we can take the average values for both processed_messagecounter metric and total_stopwatch gauge metric for comparison.

![serial baseline compare.](/blog/images/eventhub-consumer-blog-ss/serial_baseline_compare.png)


The average total duration is 30.69 msec/event and it is approximately 0.031 sec/event. The irate graph average value is 31.95 event/sec. When we compare these two, we can interpret 31.95 event/sec as 0.032 sec/event. Since results are not exact by the nature of Prometheus, we can see 0.032 sec/event for our computation and 0.031 sec/event for irate correlates. Our purpose to demonstrate this is that from this point on, we can rely on our irate graph to measure throughput after each improvement to the event hub consumer code.


### 1.2	The Message Processing Loop 

The related code part for getting the above results is in the following:

```
public async Task ProcessEventsAsync(PartitionContext context, IEnumerable<EventData> messages)
{
	stopWatchTotal.Start();
	double serviceBusAverage = 0; 
	double blobAverage = 0;
	
	int numberOfMessages = messages.Count();
	
	foreach (var eventData in messages)
	{
		var data = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);

		stopWatchServiceBus.Restart();
		await serviceBusService.SendMessage(eventData, eventData.Properties);
		stopWatchServiceBus.Stop();
		serviceBusAverage += stopWatchServiceBus.Elapsed.TotalMilliseconds;
		
		stopWatchBlob.Restart();
		await blobStorageService.StoreAsync(eventData);
		stopWatchBlob.Stop();
		blobAverage += stopWatchBlob.Elapsed.TotalMilliseconds;
		
	}
	
	ServiceBusStopWatchMetric.Set(serviceBusAverage / numberOfMessages);
	BlobStorageStopWatchMetric.Set(blobAverage / numberOfMessages);

	stopWatchCheckPoint.Start();
	await context.CheckpointAsync();
	stopWatchCheckPoint.Stop();
	CheckPointStopWatchMetric.Set(stopWatchCheckPoint.Elapsed.TotalMilliseconds / numberOfMessages);

	stopWatchTotal.Stop();
	TotalStopWatchMetric.Set(stopWatchTotal.Elapsed.TotalMilliseconds / numberOfMessages);
	ProcessedBatchCounterMetric.Inc(numberOfMessages);
}

```


## 2. Parallelize inner loop I/O operations

This scenario has also the same metrics but this time, blob and service bus send operations are made parallel for each individual event. This should increase the average rate on irate graph and decrease the stopwatch timer graph values.

### 2.1	Changes in Metrics

Same metrics are used.

### 2.1.1 Irate

As we can see in the following irate graph, the rate of increase is increased when we compare it with the baseline scenario. The average rate value for the graph in baseline was 31.95 event/sec but the current graph displays average as 43.95 event/sec.

![inloop parallel irate.](/blog/images/eventhub-consumer-blog-ss/inloop_parallel_irate.png)

### 2.1.2 Stopwatch Timers

The total amount of msec is also decreased compared to the baseline scenario. As you can see in the following graph, the average value for total_stopwatch timer metric value 21.11 msec/event is smaller than the baseline graph average value which was 30.69 msec/event. This means, our improvement to the event hub consumer increased performance.

![inloop parallel stopwatches.](/blog/images/eventhub-consumer-blog-ss/inloop_parallel_stopwatch.png)


### 2.1.3 Irate and Total Stopwatch Timer Verification

Again, we can verify the irate graph and our calculation for total duration is correlated with the following comparison of the two.

![inloop parallel compare.](/blog/images/eventhub-consumer-blog-ss/inloop_parallel_compare.png)

The average total duration is 21.14 msec/event and it is approximately 0.021 sec/event. The irate graph average value is 43.93 event/sec. When we compare these two, we can interpret 43.93 event/sec as 0.022 sec/event. We can see 0.021 sec/event for our computation and 0.022 sec/event for irate correlates.


### 2.2	The Message Processing Loop

The related code part for getting the above results is in the following:

```
public async Task ProcessEventsAsync(PartitionContext context, IEnumerable<EventData> messages)
{
	
	Stopwatch stopWatchTotal = new Stopwatch();
	Stopwatch stopWatchCheckPoint = new Stopwatch();
	int numberOfMessages = messages.Count();
	
	stopWatchTotal.Start();
	foreach (var eventData in messages)
	{
		var data = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);
		var tasks = new List<Task>();
		
		tasks.Add(
			Task.Run(async () =>
			{
				var stopWatchServiceBus = Stopwatch.StartNew();
				await serviceBusService.SendMessage(eventData, eventData.Properties);
				stopWatchServiceBus.Stop();
				ServiceBusStopWatchMetric.Set(stopWatchServiceBus.Elapsed.TotalMilliseconds);
			})
		);
		
		tasks.Add(
			Task.Run(async () =>
			{
				var stopWatchBlob = Stopwatch.StartNew();
				await blobStorageService.StoreAsync(eventData);
				stopWatchBlob.Stop();
				BlobStorageStopWatchMetric.Set(stopWatchBlob.Elapsed.TotalMilliseconds);
			})
		);
		
		await Task.WhenAll(tasks);
	}

	stopWatchCheckPoint.Start();
	await context.CheckpointAsync();
	stopWatchCheckPoint.Stop();
	CheckPointStopWatchMetric.Set(stopWatchCheckPoint.Elapsed.TotalMilliseconds / numberOfMessages);

	stopWatchTotal.Stop();
	TotalStopWatchMetric.Set(stopWatchTotal.Elapsed.TotalMilliseconds / numberOfMessages);
	ProcessedCounterMetric.Inc(numberOfMessages);
}
```

### 2.3	Comparison Results Starting with Baseline Scenario

|      Metric Name         |    Unit    |	Baseline (Avg)	| Inloop Parallel (Avg)	|
|        ---        	   |     ---    |		:---:		|			:---:		|
| total_stopwatch          | msec/event |		`30.69`		|			`21.14`		|
| servicebus_stopwatch     | msec/event |		`18.52`		|			`17.87`		|
| blobstorage_stopwatch    | msec/event |		`9.35`		|			`9.31`		|
| checkpoint_stopwatch 	   | msec/event |		`2.47`		|			`2.47`		|
| processed_messagecounter | event/sec  |		`31.95`		|			`43.93`		|


## 3. Parallelize outer loop I/O operations

In this scenario, the inner loop service bus and blob storage send operations kept blocking, but batch processing event loop is made parallel. In short, each iteration for individual events are parallel. We expect increase in throughput with parallelism.

### 3.1 Changes in Metrics

Same metrics are used.

### 3.1.1 Irate

As we can see in the following irate graph, the rate of increase is increased when we compare it with the inloop parallel scenario. The average rate value for the graph in inloop parallel scenario was 43.93 event/sec but the current graph displays average as 115.96 event/sec.

![outloop parallel irate.](/blog/images/eventhub-consumer-blog-ss/outloop_parallel_irate.png)

### 3.1.2 Stopwatch Timers

The total amount of msec is also decreased compared to the inloop parallel scenario. As you can see in the following graph, the average value for total_stopwatch timer metric value 9 msec/event is smaller than the inloop parallel average value which was 21.14 msec/event. This means, our improvement to the event hub consumer increased performance.

![outloop parallel stopwatches.](/blog/images/eventhub-consumer-blog-ss/outloop_parallel_stopwatch.png)


### 3.1.3 Irate and Total Stopwatch Timer Verification

Again, we can verify the irate graph and our calculation for total duration is correlated with the following comparison of the two.

![outloop parallel compare.](/blog/images/eventhub-consumer-blog-ss/outloop_parallel_compare.png)

The average total duration is 9 msec/event and it is 0.009 sec/event. The irate graph average value is 115.89 event/sec. When we compare these two, we can interpret 115.89 event/sec as 0.009 sec/event approximately. We can see 0.009 sec/event for our computation and 0.009 sec/event for irate correlates.

### 3.2 The Message Processing Loop

The related code part for getting the above results is in the following:

```
public async Task ProcessEventsAsync(PartitionContext context, IEnumerable<EventData> messages)
{
	
	Stopwatch stopWatchTotal = new Stopwatch();
	Stopwatch stopWatchCheckPoint = new Stopwatch();
	int numberOfMessages = messages.Count();
	
	stopWatchTotal.Start();
	await messages.ParallelForEachAsync(async eventData =>
	{
		var data = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);
		
		await Task.Run(
			async () =>
			{
				var stopWatchServiceBus = Stopwatch.StartNew();
				await serviceBusService.SendMessage(eventData, eventData.Properties);
				stopWatchServiceBus.Stop();
				ServiceBusStopWatchMetric.Set(stopWatchServiceBus.Elapsed.TotalMilliseconds);
			}
		);
		
		await Task.Run(
			async () =>
			{
				var stopWatchBlob = Stopwatch.StartNew();
				await blobStorageService.StoreAsync(eventData);
				stopWatchBlob.Stop();
				BlobStorageStopWatchMetric.Set(stopWatchBlob.Elapsed.TotalMilliseconds);
			}
		);
	}

	stopWatchCheckPoint.Start();
	await context.CheckpointAsync();
	stopWatchCheckPoint.Stop();
	CheckPointStopWatchMetric.Set(stopWatchCheckPoint.Elapsed.TotalMilliseconds / numberOfMessages);

	stopWatchTotal.Stop();
	TotalStopWatchMetric.Set(stopWatchTotal.Elapsed.TotalMilliseconds / numberOfMessages);
	ProcessedCounterMetric.Inc(numberOfMessages);
}
```

### 3.3 Comparison Results Starting with Baseline Scenario

|      Metric Name         |    Unit    |	Baseline (Avg)	| Inloop Parallel (Avg)	|	Outloop Parallel (Avg)	|
|        ---        	   |     ---    |		:---:		|			:---:		|			:---:			|
| total_stopwatch          | msec/event |		`30.69`		|			`21.14`		|			`9`				|
| servicebus_stopwatch     | msec/event |		`18.52`		|			`17.87`		|			`45`			|
| blobstorage_stopwatch    | msec/event |		`9.35`		|			`9.31`		|			`20`			|
| checkpoint_stopwatch 	   | msec/event |		`2.47`		|			`2.47`		|			`2`				|
| processed_messagecounter | event/sec  |		`31.95`		|			`43.93`		|			`115.89`		|


## 4. Parallelize in & out loop I/O operations

In this scenario, basically for each event processed in each loop iteration, service bus and blob storage send events are parallel like in the inloop parallel scenario. In addition, each iteration for individual events are also parallel like in the outloop parallel scenario. We expect small increase in throughput with this configuration.

### 4.1 Changes in Metrics

Same metrics are used.

### 4.1.1 Irate

As we can see in the following irate graph, the rate of increase is increased when we compare it with the outloop parallel scenario. The average rate value for the graph in outloop parallel scenario was 115.89 event/sec but the current graph displays average as 121 event/sec. So,  there is a small amount of increase as we expected.

![in&out parallel irate.](/blog/images/eventhub-consumer-blog-ss/in_out_parallel_irate.png)

### 4.1.2 Stopwatch Timers

The total amount of msec is also decreased compared to the outloop parallel scenario. As you can see in the following graph, the average value for total_stopwatch timer metric value 8 msec/event is smaller than the outloop parallel average value which was 9 msec/event. This means, our improvement to the event hub consumer increased performance.

![in&out parallel stopwatches.](/blog/images/eventhub-consumer-blog-ss/in_out_parallel_stopwatch.png)

### 4.1.3 Irate and Total Stopwatch Timer Verification

Again, we can verify the irate graph and our calculation for total duration is correlated with the following comparison of the two.

![in&out parallel compare.](/blog/images/eventhub-consumer-blog-ss/in_out_parallel_compare.png)

The average total duration is 8 msec/event which is 0.008 sec/event. The irate graph average value is 120 event/sec. When we compare these two, we can interpret 120 event/sec as 0.008 sec/event approximately. We can see 0.008 sec/event for our computation and 0.008 sec/event for irate correlates.

### 4.2 The Message Processing Loop

The related code part for getting the above results is in the following:

```
public async Task ProcessEventsAsync(PartitionContext context, IEnumerable<EventData> messages)
{
	
	Stopwatch stopWatchTotal = new Stopwatch();
	Stopwatch stopWatchCheckPoint = new Stopwatch();
	int numberOfMessages = messages.Count();
	
	stopWatchTotal.Start();
	await messages.ParallelForEachAsync(async eventData =>
	{
		var data = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);
		var tasks = new List<Task>();
		
		tasks.Add(
			Task.Run(async () =>
			{
				var stopWatchServiceBus = Stopwatch.StartNew();
				await serviceBusService.SendMessage(eventData, eventData.Properties);
				stopWatchServiceBus.Stop();
				ServiceBusStopWatchMetric.Set(stopWatchServiceBus.Elapsed.TotalMilliseconds);
			})
		);
		
		tasks.Add(
			Task.Run(async () =>
			{
				var stopWatchBlob = Stopwatch.StartNew();
				await blobStorageService.StoreAsync(eventData);
				stopWatchBlob.Stop();
				BlobStorageStopWatchMetric.Set(stopWatchBlob.Elapsed.TotalMilliseconds);
			})
		);
		
		await Task.WhenAll(tasks);
	}

	stopWatchCheckPoint.Start();
	await context.CheckpointAsync();
	stopWatchCheckPoint.Stop();
	CheckPointStopWatchMetric.Set(stopWatchCheckPoint.Elapsed.TotalMilliseconds / numberOfMessages);

	stopWatchTotal.Stop();
	TotalStopWatchMetric.Set(stopWatchTotal.Elapsed.TotalMilliseconds / numberOfMessages);
	ProcessedCounterMetric.Inc(numberOfMessages);
}
```

### 4.3 Comparison Results Starting with Baseline Scenario

|      Metric Name         |    Unit    |	Baseline (Avg)	| Inloop Parallel (Avg)	|	Outloop Parallel (Avg)	|	In & Out Loop Parallel (Avg)	|
|        ---        	   |     ---    |		:---:		|			:---:		|			:---:			|				:---:				|
| total_stopwatch          | msec/event |		`30.69`		|			`21.14`		|			`9`				|				`8`					|
| servicebus_stopwatch     | msec/event |		`18.52`		|			`17.87`		|			`45`			|				`39`				|
| blobstorage_stopwatch    | msec/event |		`9.35`		|			`9.31`		|			`20`			|				`13`				|
| checkpoint_stopwatch 	   | msec/event |		`2.47`		|			`2.47`		|			`2`				|				`2`					|
| processed_messagecounter | event/sec  |		`31.95`		|			`43.93`		|			`115.89`		|				`120`				|
